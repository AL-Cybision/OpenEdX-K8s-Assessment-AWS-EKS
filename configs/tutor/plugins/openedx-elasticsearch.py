from __future__ import annotations

from tutor import hooks

# Make the ELASTICSEARCH_HOST config value available to templates/patches.
# It is overridden in this project from Terraform outputs.
hooks.Filters.CONFIG_DEFAULTS.add_item(("ELASTICSEARCH_HOST", "http://elasticsearch:9200"))

LMS_PATCH = """\
# Enable Elasticsearch as the search backend
MEILISEARCH_ENABLED = False
SEARCH_ENGINE = \"search.elastic.ElasticSearchEngine\"
ELASTIC_SEARCH_CONFIG = [{\"hosts\": [\"{{ ELASTICSEARCH_HOST }}\"]}]
ELASTIC_SEARCH_INDEX_PREFIX = \"tutor_\"

# Keep MFE runtime config aligned (MFEs may read this from /api/mfe_config).
MFE_CONFIG[\"MEILISEARCH_ENABLED\"] = \"false\"
"""

CMS_PATCH = """\
# Enable Elasticsearch as the search backend
MEILISEARCH_ENABLED = False
SEARCH_ENGINE = \"search.elastic.ElasticSearchEngine\"
ELASTIC_SEARCH_CONFIG = [{\"hosts\": [\"{{ ELASTICSEARCH_HOST }}\"]}]
ELASTIC_SEARCH_INDEX_PREFIX = \"tutor_\"
"""

hooks.Filters.ENV_PATCHES.add_item(("openedx-lms-production-settings", LMS_PATCH))
hooks.Filters.ENV_PATCHES.add_item(("openedx-cms-production-settings", CMS_PATCH))
