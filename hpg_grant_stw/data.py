"""Demo data to make the grant seeker immediately usable offline."""

from hpg_grant_stw.models import GrantOpportunity, NGO

HPG_NGOS = [
    NGO(
        id="hpg-01",
        name="HPG Clean Water Coalition",
        region="East Africa",
        mission="Deliver safe water access and hygiene training to rural communities.",
        focus_areas=["water", "sanitation", "hygiene", "infrastructure"],
        annual_budget="$1.8M",
        needs=["borehole drilling", "solar pumps", "behavior change campaigns"],
        differentiators=["community-led maintenance", "local artisans", "women-led water committees"],
    ),
    NGO(
        id="hpg-02",
        name="HPG Climate Resilience Network",
        region="South Asia",
        mission="Strengthen climate resilience for smallholder farmers through training and finance.",
        focus_areas=["climate", "agriculture", "livelihoods", "finance"],
        annual_budget="$2.3M",
        needs=["drought-resistant seeds", "micro-insurance", "market linkages"],
        differentiators=["farmer field schools", "mobile agronomy coaching", "impact-linked financing"],
    ),
    NGO(
        id="hpg-03",
        name="HPG Girls Education Alliance",
        region="West Africa",
        mission="Expand access to STEM education for girls through scholarships and mentorship.",
        focus_areas=["education", "gender", "technology", "scholarships"],
        annual_budget="$1.2M",
        needs=["STEM labs", "teacher training", "mentorship networks"],
        differentiators=["alumnae mentors", "public-private partnerships", "scholar-led community projects"],
    ),
]


DEMO_GRANTS = [
    GrantOpportunity(
        id="grant-usaid-wash",
        name="USAID WASH Innovation Fund",
        funder="USAID",
        description=(
            "Supports scalable water, sanitation, and hygiene solutions with strong community"
            " engagement and sustainability plans."
        ),
        themes=["water", "sanitation", "hygiene", "innovation"],
        region="East Africa",
        amount_range=("$250k", "$1M"),
        deadline="2024-10-15",
        url="https://www.usaid.gov/",
    ),
    GrantOpportunity(
        id="grant-gates-climate",
        name="Gates Foundation Climate-Smart Agriculture",
        funder="Bill & Melinda Gates Foundation",
        description=(
            "Invests in climate adaptation for smallholder farmers, including drought-resistant"
            " crops, digital advisory tools, and inclusive finance."
        ),
        themes=["climate", "agriculture", "finance", "digital"],
        region="South Asia",
        amount_range=("$500k", "$2M"),
        deadline="2024-11-01",
        url="https://www.gatesfoundation.org/",
    ),
    GrantOpportunity(
        id="grant-unicef-girls",
        name="UNICEF Girls in STEM Challenge",
        funder="UNICEF",
        description=(
            "Funds education initiatives that improve girls' access to STEM resources, teacher"
            " training, and community support."
        ),
        themes=["education", "gender", "technology", "community"],
        region="West Africa",
        amount_range=("$150k", "$750k"),
        deadline="2024-12-05",
        url="https://www.unicef.org/",
    ),
]
