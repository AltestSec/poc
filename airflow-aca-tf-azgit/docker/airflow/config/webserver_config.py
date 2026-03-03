# ============================================================
# webserver_config.py - Airflow Webserver Configuration
# Customize authentication, RBAC, and UI settings
# ============================================================
import os
from airflow.www.fab_security.manager import AUTH_DB

# Authentication type
# AUTH_DB = database authentication (default)
# AUTH_OAUTH = OAuth
# AUTH_LDAP = LDAP
# AUTH_REMOTE_USER = remote user (e.g., reverse proxy)
AUTH_TYPE = AUTH_DB

# Flask-AppBuilder configuration
# Uncomment and customize as needed

# AUTH_ROLE_ADMIN = 'Admin'
# AUTH_ROLE_PUBLIC = 'Public'
# AUTH_USER_REGISTRATION = True
# AUTH_USER_REGISTRATION_ROLE = "Public"

# Session configuration
# PERMANENT_SESSION_LIFETIME = 1800  # 30 minutes

# Security
# WTF_CSRF_ENABLED = True
# WTF_CSRF_TIME_LIMIT = None

# Rate limiting
# AUTH_RATE_LIMITED = True
# AUTH_RATE_LIMIT = "5 per 40 second"

# Azure AD OAuth example (uncomment to use)
# from flask_appbuilder.security.manager import AUTH_OAUTH
# AUTH_TYPE = AUTH_OAUTH
# OAUTH_PROVIDERS = [{
#     'name': 'azure',
#     'icon': 'fa-windows',
#     'token_key': 'access_token',
#     'remote_app': {
#         'client_id': os.getenv('AZURE_CLIENT_ID'),
#         'client_secret': os.getenv('AZURE_CLIENT_SECRET'),
#         'api_base_url': 'https://login.microsoftonline.com/{tenant_id}/oauth2',
#         'client_kwargs': {
#             'scope': 'openid email profile',
#         },
#         'access_token_url': 'https://login.microsoftonline.com/{tenant_id}/oauth2/token',
#         'authorize_url': 'https://login.microsoftonline.com/{tenant_id}/oauth2/authorize',
#     }
# }]
