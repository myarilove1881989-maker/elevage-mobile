"""Real Django business API on an ephemeral CI PostgreSQL, HTTPS and synthetic farm.

Fixture routes exist only in this test URLconf, never in the backend application.
No request bodies, authentication headers or key material are logged.
"""
import base64
import ipaddress
import json
import os
from pathlib import Path
import ssl
import subprocess
import sys
from datetime import datetime,timedelta,timezone as dt_timezone
from socketserver import ThreadingMixIn
from wsgiref.simple_server import WSGIServer,WSGIRequestHandler,make_server

PINNED_BACKEND='3c2d1fdcb530827c0d0a46b2ff0ec109e11d40e1'
ROOT=Path(__file__).resolve().parent.parent
BACKEND=ROOT/'build'/'native-business-backend'
EVIDENCE=ROOT/'build'/'native-business-proof'
os.environ['DATABASE_URL']=''
os.environ['SECRET_KEY']='ephemeral-native-i-jwt-key-not-production'
os.environ['DJANGO_SETTINGS_MODULE']='native_business_settings'
sys.path.insert(0,str(BACKEND))
sys.modules['native_business_server']=sys.modules[__name__]
if os.environ.get('GITHUB_ACTIONS')!='true':
    raise RuntimeError('This server is restricted to the ephemeral CI runner')
if subprocess.check_output(['git','-C',str(BACKEND),'rev-parse','HEAD'],text=True).strip()!=PINNED_BACKEND:
    raise RuntimeError('Backend source differs from the validated checkpoint')

import django
django.setup()
from django.conf import settings
from django.core.management import call_command
from django.core.wsgi import get_wsgi_application
from django.db import connection
from django.http import JsonResponse
from django.urls import path,include
from django.utils import timezone
from rest_framework.decorators import api_view,permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from core.models import (User,Espece,Lot,Task,CollecteOeufs,Client,Achat,Vente,VenteOeufs,
    Payment,Lettrage,EncaissementTerrain,AffectationMouvementOeufs,
    TerrainSubmission,TerrainDecision,AuditEvent,DeviceRegistration)
from core.egg_services import sync_collection_stock_movement
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import rsa,ed25519

STATE={}
BEARER_ON_DEVICE=False

def owner_only(request):
    if request.user.pk!=STATE.get('owner'):
        raise PermissionError('Synthetic fixture owner required')

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def fixture_state(request):
    owner_only(request)
    return Response({key:value for key,value in STATE.items() if key!='collections'})

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def verify(request):
    owner_only(request)
    ids=request.data.get('operation_ids')
    assert isinstance(ids,list) and len(ids)==7 and len(set(ids))==7
    originals=list(TerrainSubmission.objects.filter(client_operation_id__in=ids).order_by('local_sequence'))
    assert len(originals)==7
    assert [r.author_user_id for r in originals]==[STATE['jean']]*6+[STATE['paul']]
    assert all(r.exploitation_id==STATE['farm'] for r in originals)
    assert Achat.objects.count()==1 and Vente.objects.count()==1 and VenteOeufs.objects.count()==1
    sale=Vente.objects.get();assert str(sale.montant_total)=='30000.00'
    assert sale.created_by_id==STATE['jean'] and sale.lot.stock==17
    cash=EncaissementTerrain.objects.get()
    assert str(cash.montant_recu)=='50000.00' and str(cash.montant_affecte)=='30000.00'
    assert str(cash.montant_a_rapprocher)=='20000.00' and cash.created_by_id==STATE['jean']
    assert Payment.objects.count()==1 and Lettrage.objects.count()==1
    allocations=list(AffectationMouvementOeufs.objects.order_by('collecte_id').values_list('collecte_id','quantite'))
    assert allocations==[(STATE['collections'][0],2),(STATE['collections'][1],2)]
    assert not AffectationMouvementOeufs.objects.filter(collecte_id=STATE['collections'][2]).exists()
    task=Task.objects.get(pk=STATE['task']);assert task.completed_by_id==STATE['jean'] and task.status=='DONE'
    assert Client.objects.get(nom='Client réel Jean').created_by_id==STATE['jean']
    assert Client.objects.get(nom='Client réel Paul').created_by_id==STATE['paul']
    assert AuditEvent.objects.filter(action='TERRAIN_RECEIVED',operation_id__in=ids).count()==7
    assert not BEARER_ON_DEVICE
    result={'verified':True,'originals':7,'jean':6,'paul':1,'stock':17,
      'cash_received':'50000.00','cash_allocated':'30000.00','cash_review':'20000.00',
      'fifo':[2,2],'future_collection_consumed':False,'device_bearer':False}
    EVIDENCE.mkdir(parents=True,exist_ok=True)
    (EVIDENCE/'server-business-verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print('REAL_SERVER_BUSINESS_VERIFIED originals=7 jean=6 paul=1 fifo=2+2 cash=50000/30000/20000',flush=True)
    return Response(result)

urlpatterns=[path('api/test-fixture/state/',fixture_state),
    path('api/test-fixture/verify/',verify),path('api/',include('core.urls'))]

def assert_database():
    conf=connection.settings_dict
    assert connection.vendor=='postgresql' and conf['HOST']=='127.0.0.1' and str(conf['PORT'])=='55438'
    assert conf['NAME']=='elevage_native_i_test' and conf['USER']=='native_i_test'
    with connection.cursor() as cursor:
        cursor.execute('SELECT current_database(),inet_server_port(),version()')
        name,port,version=cursor.fetchone()
        assert name=='elevage_native_i_test' and port==5432 and version.startswith('PostgreSQL 17.')
        cursor.execute("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public'")
        assert cursor.fetchone()[0]==0,'Fresh database required; never reset an existing database'
    print('TEST_DATABASE PostgreSQL17 host=127.0.0.1:55438 database=elevage_native_i_test production=false',flush=True)

def seed():
    password='SyntheticNativeI-2026-only'
    owner=User.objects.create_user(username='native-owner',password=password)
    farm=owner.exploitation
    farm.offline_policy_enabled=True;farm.save(update_fields=['offline_policy_enabled'])
    jean=User.objects.create_user(username='native-jean',password=password,exploitation=farm)
    paul=User.objects.create_user(username='native-paul',password=password,exploitation=farm)
    species=Espece.objects.create(exploitation=farm,nom='Espèce synthétique native')
    egglot=Lot.objects.create(exploitation=farm,espece=species,nom='Œufs natifs',type_production='OEUFS',date_debut=timezone.localdate())
    at=timezone.now()-timedelta(days=1)
    collections=[]
    for offset,count in [(-120,2),(-60,3),(1,100)]:
        row=CollecteOeufs.objects.create(exploitation=farm,lot=egglot,
          collecte_at=at+timedelta(minutes=offset),nombre_collecte=count,created_by=jean)
        sync_collection_stock_movement(row);collections.append(row.pk)
    task=Task.objects.create(exploitation=farm,title='Visite native réelle',date=timezone.localdate(),assigned_to=jean,status='IN_PROGRESS')
    STATE.update(owner=owner.pk,farm=farm.pk,jean=jean.pk,paul=paul.pk,species=species.pk,
      egg_lot=egglot.pk,egg_sale_at=at.isoformat(),task=task.pk,collections=collections)
    key=ed25519.Ed25519PrivateKey.generate()
    settings.OFFLINE_SIGNING_PRIVATE_KEY=key.private_bytes(serialization.Encoding.PEM,
      serialization.PrivateFormat.PKCS8,serialization.NoEncryption()).decode()

def certificates():
    private=ROOT/'build'/'native-business-private';private.mkdir(parents=True,exist_ok=True)
    now=datetime.now(dt_timezone.utc)
    ca_key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
    name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'Ephemeral native I CA')])
    ca=(x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(ca_key.public_key())
      .serial_number(x509.random_serial_number()).not_valid_before(now-timedelta(minutes=5))
      .not_valid_after(now+timedelta(days=2)).add_extension(x509.BasicConstraints(ca=True,path_length=0),critical=True)
      .sign(ca_key,hashes.SHA256()))
    key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
    cert=(x509.CertificateBuilder().subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'10.0.2.2')]))
      .issuer_name(name).public_key(key.public_key()).serial_number(x509.random_serial_number())
      .not_valid_before(now-timedelta(minutes=5)).not_valid_after(now+timedelta(days=1))
      .add_extension(x509.SubjectAlternativeName([x509.IPAddress(ipaddress.ip_address('10.0.2.2')),
        x509.IPAddress(ipaddress.ip_address('127.0.0.1')),x509.DNSName('localhost')]),critical=False)
      .add_extension(x509.BasicConstraints(ca=False,path_length=None),critical=True).sign(ca_key,hashes.SHA256()))
    (private/'server.pem').write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    (private/'key.pem').write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
    os.chmod(private/'key.pem',0o600)
    (private/'ca.pem').write_bytes(ca.public_bytes(serialization.Encoding.PEM))
    return private

class QuietHandler(WSGIRequestHandler):
    def log_message(self,*args):pass
class ThreadedServer(ThreadingMixIn,WSGIServer):
    daemon_threads=True

def main():
    assert_database()
    call_command('migrate',verbosity=1,interactive=False)
    call_command('check');call_command('makemigrations',check=True,dry_run=True)
    seed();private=certificates()
    app=get_wsgi_application()
    def inspected(environ,start_response):
        global BEARER_ON_DEVICE
        if environ['PATH_INFO'] in ['/api/offline/transport-challenge/','/api/offline/submissions/','/api/offline/submissions/status/']:
            BEARER_ON_DEVICE|=bool(environ.get('HTTP_AUTHORIZATION'))
        return app(environ,start_response)
    server=make_server('127.0.0.1',9443,inspected,server_class=ThreadedServer,handler_class=QuietHandler)
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(private/'server.pem',private/'key.pem')
    server.socket=context.wrap_socket(server.socket,server_side=True)
    (private/'ready').write_text('READY\n')
    print('REAL_NATIVE_TEST_SERVER_READY https://10.0.2.2:9443/api production=false',flush=True)
    server.serve_forever()

if __name__=='__main__':main()
