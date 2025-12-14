-- HPG Grant STW Supabase portfolio schema improvements
-- Provides normalized tables for NGOs, grants, alignments, proposals, and contacts
-- with constraints and indexes to keep data clean and queryable.

-- Extensions
create extension if not exists "pgcrypto";
create extension if not exists "citext";

-- Utility to maintain updated_at timestamps
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- Organizations (HPG NGOs)
create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  slug citext not null unique,
  name text not null,
  mission text,
  region text,
  website text,
  contact_email citext,
  focus_areas text[] not null default '{}',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint contact_email_format check (contact_email is null or position('@' in contact_email) > 1)
);
create trigger set_organizations_updated_at
before update on public.organizations
for each row execute function public.set_updated_at();
create index if not exists organizations_focus_areas_gin on public.organizations using gin (focus_areas);

-- Grants catalog
create table if not exists public.grants (
  id uuid primary key default gen_random_uuid(),
  source text not null,
  external_id text,
  title text not null,
  summary text,
  region text,
  thematic_tags text[] not null default '{}',
  deadline_date date,
  amount_min numeric,
  amount_max numeric,
  currency char(3) not null default 'USD',
  url text,
  status text not null default 'open' check (status in ('open','upcoming','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint grants_unique_source_id unique (source, external_id)
);
create trigger set_grants_updated_at
before update on public.grants
for each row execute function public.set_updated_at();
create index if not exists grants_thematic_tags_gin on public.grants using gin (thematic_tags);
create index if not exists grants_search_idx on public.grants using gin (to_tsvector('english', coalesce(title,'') || ' ' || coalesce(summary,'')));
create index if not exists grants_deadline_idx on public.grants (deadline_date);

-- Grant contacts (program officers, inboxes, etc.)
create table if not exists public.grant_contacts (
  id uuid primary key default gen_random_uuid(),
  grant_id uuid not null references public.grants(id) on delete cascade,
  contact_name text not null,
  contact_email citext,
  role text,
  phone text,
  notes text,
  created_at timestamptz not null default now()
);
create index if not exists grant_contacts_grant_id_idx on public.grant_contacts (grant_id);

-- Alignment scores between NGOs and grants
create table if not exists public.grant_alignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  grant_id uuid not null references public.grants(id) on delete cascade,
  score numeric(5,2) not null check (score >= 0 and score <= 100),
  strengths text,
  gaps text,
  generated_on timestamptz not null default now(),
  constraint grant_alignments_unique unique (organization_id, grant_id)
);
create index if not exists grant_alignments_org_idx on public.grant_alignments (organization_id);
create index if not exists grant_alignments_grant_idx on public.grant_alignments (grant_id);

-- Proposal drafts and submissions
create table if not exists public.proposals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  grant_id uuid not null references public.grants(id) on delete cascade,
  status text not null default 'draft' check (status in ('draft','in_review','submitted','awarded','declined')),
  draft_url text,
  narrative_md text,
  budget_notes text,
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint proposals_unique_submission unique (organization_id, grant_id)
);
create trigger set_proposals_updated_at
before update on public.proposals
for each row execute function public.set_updated_at();
create index if not exists proposals_org_idx on public.proposals (organization_id);
create index if not exists proposals_grant_idx on public.proposals (grant_id);
create index if not exists proposals_status_idx on public.proposals (status);

-- Simple milestones and tasks for proposal workflow
create table if not exists public.proposal_tasks (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references public.proposals(id) on delete cascade,
  title text not null,
  due_date date,
  assignee text,
  status text not null default 'pending' check (status in ('pending','in_progress','blocked','done')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger set_proposal_tasks_updated_at
before update on public.proposal_tasks
for each row execute function public.set_updated_at();
create index if not exists proposal_tasks_proposal_idx on public.proposal_tasks (proposal_id);
create index if not exists proposal_tasks_status_idx on public.proposal_tasks (status);

-- View to quickly see open grants with best-known alignments
create or replace view public.open_grants_with_alignments as
select
  g.id as grant_id,
  g.title,
  g.source,
  g.region,
  g.deadline_date,
  g.thematic_tags,
  ga.organization_id,
  ga.score,
  ga.strengths,
  ga.gaps,
  ga.generated_on
from public.grants g
left join public.grant_alignments ga on ga.grant_id = g.id
where g.status = 'open' and (g.deadline_date is null or g.deadline_date >= current_date);
