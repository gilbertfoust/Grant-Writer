-- Supabase PostgreSQL "Portfolio Edition" schema for Grant Writing SaaS
-- Focus: HPG managing many NGOs (multi-org membership, portfolio workflow, vector search)
-- Generated: 2025-12-13
--
-- Notes:
-- - Uses Supabase Auth (auth.users) for identities.
-- - Keeps org-scoped data isolated via RLS; HPG staff can access many orgs via membership or platform admin.
-- - Uses pgvector for embeddings and ivfflat indexes for similarity search.
-- - Stores NGO "fit" embedding separately from "voice" embedding.

BEGIN;

-- Extensions (idempotent)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- -----------------------------------------------------------------------------
-- Helpers: timestamps
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- Users: profile data (Supabase Auth users live in auth.users)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_profiles (
  user_id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name       TEXT,
  email              TEXT, -- optional mirror for convenience (auth.users is canonical)
  is_platform_admin  BOOLEAN NOT NULL DEFAULT FALSE, -- HPG superuser override
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_user_profiles_updated
BEFORE UPDATE ON public.user_profiles
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Organizations (NGO profiles)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.organizations (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name                    TEXT NOT NULL,
  mission_statement       TEXT,
  vision_statement        TEXT,
  core_values             JSONB,        -- array
  voice_profile           JSONB,        -- extracted tone attributes
  voice_embedding         VECTOR(1536), -- writing style / tone
  org_search_profile      TEXT,         -- normalized "what we do" text (editable summary)
  org_search_embedding    VECTOR(1536), -- semantic match for grants (fit embedding)
  geographic_focus        JSONB,        -- array (countries/regions)
  populations_served      JSONB,        -- array (youth, women, etc.)
  annual_budget           NUMERIC,
  staff_count             INTEGER,
  year_founded            INTEGER,
  ein                     TEXT UNIQUE,
  nonprofit_classification TEXT,
  contact_information     JSONB,
  created_by              UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at              TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_organizations_name_trgm ON public.organizations USING gin (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_organizations_core_values_gin ON public.organizations USING gin (core_values);
CREATE INDEX IF NOT EXISTS idx_organizations_voice_profile_gin ON public.organizations USING gin (voice_profile);
CREATE INDEX IF NOT EXISTS idx_organizations_geo_gin ON public.organizations USING gin (geographic_focus);
CREATE INDEX IF NOT EXISTS idx_organizations_pop_gin ON public.organizations USING gin (populations_served);

CREATE INDEX IF NOT EXISTS idx_organizations_org_search_embedding_ivfflat
  ON public.organizations USING ivfflat (org_search_embedding vector_cosine_ops) WITH (lists = 100);

CREATE INDEX IF NOT EXISTS idx_organizations_voice_embedding_ivfflat
  ON public.organizations USING ivfflat (voice_embedding vector_cosine_ops) WITH (lists = 100);

CREATE TRIGGER trg_organizations_updated
BEFORE UPDATE ON public.organizations
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Organization membership (HPG staff can belong to many NGOs)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'org_role') THEN
    CREATE TYPE public.org_role AS ENUM (
      'org_owner',
      'org_admin',
      'writer',
      'reviewer',
      'viewer',
      'portfolio_manager' -- HPG staff assigned to this org
    );
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS public.organization_members (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role            public.org_role NOT NULL DEFAULT 'viewer',
  status          TEXT NOT NULL DEFAULT 'active', -- active/invited/suspended
  added_by        UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (organization_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_org_members_org ON public.organization_members(organization_id);
CREATE INDEX IF NOT EXISTS idx_org_members_user ON public.organization_members(user_id);

CREATE TRIGGER trg_org_members_updated
BEFORE UPDATE ON public.organization_members
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Auto-add org creator as org_owner
CREATE OR REPLACE FUNCTION public.add_creator_as_owner()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.organization_members (organization_id, user_id, role, added_by)
  VALUES (NEW.id, NEW.created_by, 'org_owner', NEW.created_by)
  ON CONFLICT (organization_id, user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_org_creator_owner ON public.organizations;
CREATE TRIGGER trg_org_creator_owner
AFTER INSERT ON public.organizations
FOR EACH ROW EXECUTE FUNCTION public.add_creator_as_owner();

-- -----------------------------------------------------------------------------
-- Organization projects (structured "focus projects")
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.organization_projects (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name             TEXT NOT NULL,
  summary          TEXT,
  sectors          JSONB,        -- array
  locations        JSONB,        -- array (countries/regions)
  populations      JSONB,        -- array
  start_date       DATE,
  end_date         DATE,
  status           TEXT NOT NULL DEFAULT 'active',
  outcomes         JSONB,        -- e.g., KPIs/outcomes
  budget_range_min NUMERIC,
  budget_range_max NUMERIC,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at       TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_org_projects_org ON public.organization_projects(organization_id);
CREATE INDEX IF NOT EXISTS idx_org_projects_sectors_gin ON public.organization_projects USING gin (sectors);
CREATE INDEX IF NOT EXISTS idx_org_projects_locations_gin ON public.organization_projects USING gin (locations);
CREATE INDEX IF NOT EXISTS idx_org_projects_populations_gin ON public.organization_projects USING gin (populations);

CREATE TRIGGER trg_org_projects_updated
BEFORE UPDATE ON public.organization_projects
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Funders (optional canonical entities)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.funders (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name           TEXT NOT NULL,
  type           TEXT NOT NULL, -- government/foundation/corporate
  focus_areas    JSONB,
  past_grants    JSONB,
  contact_info   JSONB,
  website_url    TEXT,
  last_updated   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_funders_name_trgm ON public.funders USING gin (name gin_trgm_ops);

CREATE TRIGGER trg_funders_updated
BEFORE UPDATE ON public.funders
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Grants (opportunities)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.grants (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  external_id           TEXT UNIQUE,
  title                 TEXT NOT NULL,
  description           TEXT,
  funder_name           TEXT,
  funder_type           TEXT,
  funder_id             UUID REFERENCES public.funders(id) ON DELETE SET NULL,
  funding_amount_min    NUMERIC,
  funding_amount_max    NUMERIC,
  deadline_date         DATE,
  eligibility_criteria  JSONB,
  cfda_number           TEXT,
  source_database       TEXT,
  source_url            TEXT,
  funding_mechanism     TEXT,
  status                TEXT, -- open/closing_soon/closed
  category              JSONB, -- tags
  grant_embedding       VECTOR(1536),
  scraped_date          DATE,
  last_updated          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at            TIMESTAMPTZ,
  -- Full-text search support (optional hybrid search)
  search_tsv            TSVECTOR GENERATED ALWAYS AS (
    to_tsvector('english', coalesce(title,'') || ' ' || coalesce(description,''))
  ) STORED
);

CREATE INDEX IF NOT EXISTS idx_grants_deadline ON public.grants(deadline_date);
CREATE INDEX IF NOT EXISTS idx_grants_status ON public.grants(status);
CREATE INDEX IF NOT EXISTS idx_grants_funder ON public.grants(funder_name);
CREATE INDEX IF NOT EXISTS idx_grants_category_gin ON public.grants USING gin (category);
CREATE INDEX IF NOT EXISTS idx_grants_eligibility_gin ON public.grants USING gin (eligibility_criteria);
CREATE INDEX IF NOT EXISTS idx_grants_search_tsv ON public.grants USING gin (search_tsv);

CREATE INDEX IF NOT EXISTS idx_grants_embedding_ivfflat
  ON public.grants USING ivfflat (grant_embedding vector_cosine_ops) WITH (lists = 100);

CREATE TRIGGER trg_grants_updated
BEFORE UPDATE ON public.grants
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Grant change log (optional trust feature: track deadline/eligibility changes)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.grant_change_log (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grant_id     UUID NOT NULL REFERENCES public.grants(id) ON DELETE CASCADE,
  changed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  changed_by   UUID REFERENCES auth.users(id) ON DELETE SET NULL, -- usually platform/service user
  change_type  TEXT NOT NULL, -- deadline_change/eligibility_change/amount_change/etc
  before       JSONB,
  after        JSONB
);

CREATE INDEX IF NOT EXISTS idx_grant_change_log_grant ON public.grant_change_log(grant_id);

-- -----------------------------------------------------------------------------
-- Organizational documents (PDFs) + embeddings
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.organizational_documents (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id          UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  document_type            TEXT NOT NULL, -- annual_report/strategic_plan/etc.
  file_path                TEXT NOT NULL, -- Supabase Storage path
  file_name                TEXT NOT NULL,
  mime_type                TEXT,
  extracted_text           TEXT,
  extracted_voice_elements JSONB,
  document_embedding       VECTOR(1536),
  uploaded_by              UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  uploaded_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processing_status        TEXT NOT NULL DEFAULT 'pending',
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at               TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_org_docs_org ON public.organizational_documents(organization_id);
CREATE INDEX IF NOT EXISTS idx_documents_voice_elements_gin ON public.organizational_documents USING gin (extracted_voice_elements);

CREATE INDEX IF NOT EXISTS idx_documents_embedding_ivfflat
  ON public.organizational_documents USING ivfflat (document_embedding vector_cosine_ops) WITH (lists = 100);

CREATE TRIGGER trg_documents_updated
BEFORE UPDATE ON public.organizational_documents
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Grant matches (persistent ranked results)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.grant_matches (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id    UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  grant_id           UUID NOT NULL REFERENCES public.grants(id) ON DELETE CASCADE,
  match_score        NUMERIC NOT NULL, -- 0..100
  alignment_factors  JSONB,
  matched_date       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  user_viewed        BOOLEAN NOT NULL DEFAULT FALSE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at         TIMESTAMPTZ,
  UNIQUE (organization_id, grant_id)
);

CREATE INDEX IF NOT EXISTS idx_matches_org ON public.grant_matches(organization_id);
CREATE INDEX IF NOT EXISTS idx_matches_grant ON public.grant_matches(grant_id);

CREATE TRIGGER trg_matches_updated
BEFORE UPDATE ON public.grant_matches
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Grant assignments / recommendations (HPG pushes opportunities to NGOs)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'assignment_status') THEN
    CREATE TYPE public.assignment_status AS ENUM (
      'recommended',
      'qualified',
      'loi_planned',
      'drafting',
      'in_review',
      'submitted',
      'won',
      'lost',
      'archived'
    );
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS public.grant_assignments (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  grant_id         UUID NOT NULL REFERENCES public.grants(id) ON DELETE CASCADE,
  assigned_by      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  assigned_to      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  status           public.assignment_status NOT NULL DEFAULT 'recommended',
  priority         INTEGER NOT NULL DEFAULT 3, -- 1 high, 5 low
  due_date         DATE,
  notes            TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at       TIMESTAMPTZ,
  UNIQUE (organization_id, grant_id)
);

CREATE INDEX IF NOT EXISTS idx_assignments_org ON public.grant_assignments(organization_id);
CREATE INDEX IF NOT EXISTS idx_assignments_status ON public.grant_assignments(status);
CREATE INDEX IF NOT EXISTS idx_assignments_due ON public.grant_assignments(due_date);

CREATE TRIGGER trg_assignments_updated
BEFORE UPDATE ON public.grant_assignments
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Drafts + version history
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.grant_drafts (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grant_id               UUID NOT NULL REFERENCES public.grants(id) ON DELETE CASCADE,
  organization_id        UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  created_by             UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  assigned_to            UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  draft_title            TEXT,
  prompt_version         TEXT,
  ai_model_used          TEXT,
  funder_alignment_score NUMERIC,
  voice_alignment_score  NUMERIC,
  status                 TEXT NOT NULL DEFAULT 'draft',
  current_version_id     UUID, -- FK added after versions table exists
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at             TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_grant_drafts_org ON public.grant_drafts(organization_id);
CREATE INDEX IF NOT EXISTS idx_grant_drafts_grant ON public.grant_drafts(grant_id);

CREATE TRIGGER trg_grant_drafts_updated
BEFORE UPDATE ON public.grant_drafts
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE IF NOT EXISTS public.grant_draft_versions (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  draft_id            UUID NOT NULL REFERENCES public.grant_drafts(id) ON DELETE CASCADE,
  version_number      INTEGER NOT NULL,
  draft_sections      JSONB NOT NULL, -- array of {section_type, section_content, ...}
  user_edits          JSONB,
  generated_timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ai_model_used       TEXT,
  prompt_version      TEXT,
  previous_version_id UUID REFERENCES public.grant_draft_versions(id) ON DELETE SET NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at          TIMESTAMPTZ,
  UNIQUE (draft_id, version_number)
);

CREATE INDEX IF NOT EXISTS idx_draft_versions_draft ON public.grant_draft_versions(draft_id);

CREATE TRIGGER trg_draft_versions_updated
BEFORE UPDATE ON public.grant_draft_versions
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Add FK now that both tables exist (avoids ordering issues)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'fk_current_version_portfolio'
      AND table_name = 'grant_drafts'
      AND table_schema = 'public'
  ) THEN
    ALTER TABLE public.grant_drafts
      ADD CONSTRAINT fk_current_version_portfolio
      FOREIGN KEY (current_version_id)
      REFERENCES public.grant_draft_versions(id)
      ON DELETE SET NULL;
  END IF;
END$$;

-- -----------------------------------------------------------------------------
-- Notifications (alerts, deadline reminders, grant changes)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
  type            TEXT NOT NULL, -- match/new_grant/deadline/grant_change/comment/etc
  title           TEXT NOT NULL,
  body            TEXT,
  payload         JSONB,
  is_read         BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_org ON public.notifications(organization_id);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON public.notifications(user_id, is_read);

-- -----------------------------------------------------------------------------
-- Operational: API sources (scraper health)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.api_sources (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_name  TEXT NOT NULL,
  api_endpoint TEXT,
  last_scraped TIMESTAMPTZ,
  record_count INTEGER,
  status       TEXT,
  error_logs   JSONB,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at   TIMESTAMPTZ
);

CREATE TRIGGER trg_api_sources_updated
BEFORE UPDATE ON public.api_sources
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- RLS (Row Level Security) Scaffold
-- =============================================================================

-- Helper functions (SECURITY DEFINER) to use inside policies
CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((
    SELECT up.is_platform_admin
    FROM public.user_profiles up
    WHERE up.user_id = auth.uid()
  ), FALSE);
$$;

CREATE OR REPLACE FUNCTION public.is_org_member(p_org_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.organization_members m
    WHERE m.organization_id = p_org_id
      AND m.user_id = auth.uid()
      AND m.status = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION public.has_org_role(p_org_id UUID, p_roles public.org_role[])
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.organization_members m
    WHERE m.organization_id = p_org_id
      AND m.user_id = auth.uid()
      AND m.status = 'active'
      AND m.role = ANY(p_roles)
  );
$$;

-- Enable RLS
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organizational_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.grant_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.grant_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.grant_drafts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.grant_draft_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.api_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.grant_change_log ENABLE ROW LEVEL SECURITY;
-- Grants and funders are typically readable to all authenticated users; we still can enable RLS and allow selects.
ALTER TABLE public.grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.funders ENABLE ROW LEVEL SECURITY;

-- user_profiles policies
DROP POLICY IF EXISTS "user_profiles_select_own_or_admin" ON public.user_profiles;
CREATE POLICY "user_profiles_select_own_or_admin"
  ON public.user_profiles
  FOR SELECT
  USING (user_id = auth.uid() OR public.is_platform_admin());

DROP POLICY IF EXISTS "user_profiles_insert_own" ON public.user_profiles;
CREATE POLICY "user_profiles_insert_own"
  ON public.user_profiles
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "user_profiles_update_own_or_admin" ON public.user_profiles;
CREATE POLICY "user_profiles_update_own_or_admin"
  ON public.user_profiles
  FOR UPDATE
  USING (user_id = auth.uid() OR public.is_platform_admin())
  WITH CHECK (user_id = auth.uid() OR public.is_platform_admin());

-- organizations policies
DROP POLICY IF EXISTS "organizations_select_member_or_admin" ON public.organizations;
CREATE POLICY "organizations_select_member_or_admin"
  ON public.organizations
  FOR SELECT
  USING (public.is_platform_admin() OR public.is_org_member(id));

DROP POLICY IF EXISTS "organizations_insert_authenticated" ON public.organizations;
CREATE POLICY "organizations_insert_authenticated"
  ON public.organizations
  FOR INSERT
  WITH CHECK (auth.uid() = created_by);

DROP POLICY IF EXISTS "organizations_update_owner_admin_or_platform" ON public.organizations;
CREATE POLICY "organizations_update_owner_admin_or_platform"
  ON public.organizations
  FOR UPDATE
  USING (public.is_platform_admin() OR public.has_org_role(id, ARRAY['org_owner','org_admin']::public.org_role[]))
  WITH CHECK (public.is_platform_admin() OR public.has_org_role(id, ARRAY['org_owner','org_admin']::public.org_role[]));

-- organization_members policies
DROP POLICY IF EXISTS "org_members_select_self_or_admin" ON public.organization_members;
CREATE POLICY "org_members_select_self_or_admin"
  ON public.organization_members
  FOR SELECT
  USING (public.is_platform_admin() OR user_id = auth.uid() OR public.is_org_member(organization_id));

DROP POLICY IF EXISTS "org_members_insert_owner_admin_or_platform" ON public.organization_members;
CREATE POLICY "org_members_insert_owner_admin_or_platform"
  ON public.organization_members
  FOR INSERT
  WITH CHECK (
    public.is_platform_admin()
    OR public.has_org_role(organization_id, ARRAY['org_owner','org_admin']::public.org_role[])
  );

DROP POLICY IF EXISTS "org_members_update_owner_admin_or_platform" ON public.organization_members;
CREATE POLICY "org_members_update_owner_admin_or_platform"
  ON public.organization_members
  FOR UPDATE
  USING (
    public.is_platform_admin()
    OR public.has_org_role(organization_id, ARRAY['org_owner','org_admin']::public.org_role[])
  )
  WITH CHECK (
    public.is_platform_admin()
    OR public.has_org_role(organization_id, ARRAY['org_owner','org_admin']::public.org_role[])
  );

-- organization_projects policies
DROP POLICY IF EXISTS "org_projects_select_member_or_admin" ON public.organization_projects;
CREATE POLICY "org_projects_select_member_or_admin"
  ON public.organization_projects
  FOR SELECT
  USING (public.is_platform_admin() OR public.is_org_member(organization_id));

DROP POLICY IF EXISTS "org_projects_write_owner_admin_writer_or_platform" ON public.organization_projects;
CREATE POLICY "org_projects_write_owner_admin_writer_or_platform"
  ON public.organization_projects
  FOR ALL
  USING (
    public.is_platform_admin()
    OR public.has_org_role(organization_id, ARRAY['org_owner','org_admin','writer','portfolio_manager']::public.org_role[])
  )
  WITH CHECK (
    public.is_platform_admin()
    OR public.has_org_role(organization_id, ARRAY['org_owner','org_admin','writer','portfolio_manager']::public.org_role[])
  );

-- organizational_documents policies
DROP POLICY IF EXISTS "org_docs_select_member_or_admin" ON public.organizational_documents;
CREATE POLICY "org_docs_select_member_or_admin"
  ON public.organizational_documents
  FOR SELECT
  USING (public.is_platform_admin() OR public.is_org_member(organization_id));

DROP POLICY IF EXISTS "org_docs_insert_member_or_admin" ON public.organizational_documents;
CREATE POLICY "org_docs_insert_member_or_admin"
  ON public.organizational_documents
  FOR INSERT
  WITH CHECK (public.is_platform_admin() OR public.is_org_member(organization_id));

DROP POLICY IF EXISTS "org_docs_update_owner_admin_or_platform" ON public.organizational_documents;
CREATE POLICY "org_docs_update_owner_admin_or_platform"
  ON public.organizational_documents
  FOR UPDATE
  USING (
    public.is_platform_admin()
    OR public.has_org_role(organization_id, ARRAY['org_owner','org_admin','portfolio_manager']::public.org_role[])
  )
  WITH CHECK (
    public.is_platform_admin()
    OR public.has_org_role(organization_id, ARRAY['org_owner','org_admin','portfolio_manager']::public.org_role[])
  );

-- grants policies (readable for authenticated; write restricted to platform admin)
DROP POLICY IF EXISTS "grants_select_authenticated" ON public.grants;
CREATE POLICY "grants_select_authenticated"
  ON public.grants
  FOR SELECT
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "grants_write_platform_admin" ON public.grants;
CREATE POLICY "grants_write_platform_admin"
  ON public.grants
  FOR ALL
  USING (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

-- funders policies (readable for authenticated; write restricted to platform admin)
DROP POLICY IF EXISTS "funders_select_authenticated" ON public.funders;
CREATE POLICY "funders_select_authenticated"
  ON public.funders
  FOR SELECT
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "funders_write_platform_admin" ON public.funders;
CREATE POLICY "funders_write_platform_admin"
  ON public.funders
  FOR ALL
  USING (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

-- grant_matches policies
DROP POLICY IF EXISTS "matches_select_member_or_admin" ON public.grant_matches;
CREATE POLICY "matches_select_member_or_admin"
  ON public.grant_matches
  FOR SELECT
  USING (public.is_platform_admin() OR public.is_org_member(organization_id));

DROP POLICY IF EXISTS "matches_write_platform_or_portfolio" ON public.grant_matches;
CREATE POLICY "matches_write_platform_or_portfolio"
  ON public.grant_matches
  FOR ALL
  USING (public.is_platform_admin() OR public.has_org_role(organization_id, ARRAY['portfolio_manager','org_owner','org_admin']::public.org_role[]))
  WITH CHECK (public.is_platform_admin() OR public.has_org_role(organization_id, ARRAY['portfolio_manager','org_owner','org_admin']::public.org_role[]));

-- grant_assignments policies
DROP POLICY IF EXISTS "assignments_select_member_or_admin" ON public.grant_assignments;
CREATE POLICY "assignments_select_member_or_admin"
  ON public.grant_assignments
  FOR SELECT
  USING (public.is_platform_admin() OR public.is_org_member(organization_id));

DROP POLICY IF EXISTS "assignments_write_platform_or_portfolio" ON public.grant_assignments;
CREATE POLICY "assignments_write_platform_or_portfolio"
  ON public.grant_assignments
  FOR ALL
  USING (public.is_platform_admin() OR public.has_org_role(organization_id, ARRAY['portfolio_manager','org_owner','org_admin']::public.org_role[]))
  WITH CHECK (public.is_platform_admin() OR public.has_org_role(organization_id, ARRAY['portfolio_manager','org_owner','org_admin']::public.org_role[]));

-- drafts policies
DROP POLICY IF EXISTS "drafts_select_member_or_admin" ON public.grant_drafts;
CREATE POLICY "drafts_select_member_or_admin"
  ON public.grant_drafts
  FOR SELECT
  USING (public.is_platform_admin() OR public.is_org_member(organization_id));

DROP POLICY IF EXISTS "drafts_write_owner_admin_writer_portfolio_or_platform" ON public.grant_drafts;
CREATE POLICY "drafts_write_owner_admin_writer_portfolio_or_platform"
  ON public.grant_drafts
  FOR ALL
  USING (
    public.is_platform_admin()
    OR public.has_org_role(organization_id, ARRAY['org_owner','org_admin','writer','portfolio_manager']::public.org_role[])
  )
  WITH CHECK (
    public.is_platform_admin()
    OR public.has_org_role(organization_id, ARRAY['org_owner','org_admin','writer','portfolio_manager']::public.org_role[])
  );

-- draft versions policies (inherit access via parent draft)
DROP POLICY IF EXISTS "draft_versions_select_via_draft" ON public.grant_draft_versions;
CREATE POLICY "draft_versions_select_via_draft"
  ON public.grant_draft_versions
  FOR SELECT
  USING (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1 FROM public.grant_drafts d
      WHERE d.id = draft_id
        AND public.is_org_member(d.organization_id)
    )
  );

DROP POLICY IF EXISTS "draft_versions_write_via_draft" ON public.grant_draft_versions;
CREATE POLICY "draft_versions_write_via_draft"
  ON public.grant_draft_versions
  FOR INSERT
  WITH CHECK (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1 FROM public.grant_drafts d
      WHERE d.id = draft_id
        AND public.has_org_role(d.organization_id, ARRAY['org_owner','org_admin','writer','portfolio_manager']::public.org_role[])
    )
  );

-- notifications policies
DROP POLICY IF EXISTS "notifications_select_own_or_member_or_admin" ON public.notifications;
CREATE POLICY "notifications_select_own_or_member_or_admin"
  ON public.notifications
  FOR SELECT
  USING (
    public.is_platform_admin()
    OR user_id = auth.uid()
    OR (organization_id IS NOT NULL AND public.is_org_member(organization_id))
  );

DROP POLICY IF EXISTS "notifications_update_own_or_admin" ON public.notifications;
CREATE POLICY "notifications_update_own_or_admin"
  ON public.notifications
  FOR UPDATE
  USING (public.is_platform_admin() OR user_id = auth.uid())
  WITH CHECK (public.is_platform_admin() OR user_id = auth.uid());

-- api_sources + grant_change_log: platform-only
DROP POLICY IF EXISTS "api_sources_platform_only" ON public.api_sources;
CREATE POLICY "api_sources_platform_only"
  ON public.api_sources
  FOR ALL
  USING (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS "grant_change_log_platform_only" ON public.grant_change_log;
CREATE POLICY "grant_change_log_platform_only"
  ON public.grant_change_log
  FOR ALL
  USING (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

COMMIT;
