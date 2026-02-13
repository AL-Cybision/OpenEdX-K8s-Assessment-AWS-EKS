from __future__ import annotations

from tutor import hooks

# Make the ELASTICSEARCH_HOST config value available to templates/patches.
# It is overridden in this project from Terraform outputs.
hooks.Filters.CONFIG_DEFAULTS.add_item(("ELASTICSEARCH_HOST", "http://elasticsearch:9200"))

LMS_PATCH = """\
# Enable Elasticsearch as the search backend
SEARCH_ENGINE = \"search.elastic.ElasticSearchEngine\"
ELASTIC_SEARCH_CONFIG = [\"{{ ELASTICSEARCH_HOST }}\"]
ELASTIC_SEARCH_INDEX_PREFIX = \"tutor_\"
"""

CMS_PATCH = """\
# Enable Elasticsearch as the search backend
SEARCH_ENGINE = \"search.elastic.ElasticSearchEngine\"
ELASTIC_SEARCH_CONFIG = [\"{{ ELASTICSEARCH_HOST }}\"]
ELASTIC_SEARCH_INDEX_PREFIX = \"tutor_\"
"""

hooks.Filters.ENV_PATCHES.add_item(("openedx-lms-production-settings", LMS_PATCH))
hooks.Filters.ENV_PATCHES.add_item(("openedx-cms-production-settings", CMS_PATCH))
