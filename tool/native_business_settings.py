"""CI-only PostgreSQL identity. Deployment URLs are never consulted."""
import os
if os.environ.get('GITHUB_ACTIONS')!='true' or os.environ.get('DATABASE_URL'):
    raise RuntimeError('Ephemeral CI with empty DATABASE_URL required')
from config.settings import *
DATABASES={'default':{'ENGINE':'django.db.backends.postgresql',
    'NAME':'elevage_native_i_test','USER':'native_i_test','PASSWORD':'synthetic-native-i-password',
    'HOST':'127.0.0.1','PORT':'55438','CONN_MAX_AGE':0}}
ALLOWED_HOSTS=['127.0.0.1','localhost','10.0.2.2']
ROOT_URLCONF='native_business_server'
DEBUG=False
SECURE_SSL_REDIRECT=False
OFFLINE_AUTHORIZATION_DAYS=3
OFFLINE_SIGNING_KEY_ID='ephemeral-native-i'
