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
import threading
import traceback
from functools import wraps
from datetime import datetime,timedelta,timezone as dt_timezone
from socketserver import ThreadingMixIn
from wsgiref.simple_server import WSGIServer,WSGIRequestHandler,make_server

PINNED_BACKEND='b815c45b08cceb2827ded119cf0c07ea1119dc46'
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
from rest_framework_simplejwt.tokens import RefreshToken
from core.models import (User,Espece,Lot,Task,CollecteOeufs,Client,Achat,Vente,VenteOeufs,
    CategorieDepense,Depense,ConsommationAliment,PeseeProduction,Mouvement,
    Payment,Lettrage,EncaissementTerrain,AffectationMouvementOeufs,
    TerrainSubmission,TerrainDecision,AuditEvent,DeviceRegistration)
from core.egg_services import sync_collection_stock_movement
from core.cache_views import lot_stock_queryset
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import rsa,ed25519

STATE={}
BEARER_ON_DEVICE=False
CONTROLLED_OFFSET=0

class ControlledDateTime(datetime):
    @classmethod
    def now(cls,tz=None):
        return datetime.now(tz)+timedelta(seconds=CONTROLLED_OFFSET)

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def advance_fixture_clock(request):
    owner_only(request)
    global CONTROLLED_OFFSET
    seconds=request.data['seconds']
    assert type(seconds) is int and seconds in [21600,86400,345600,604800]
    assert seconds>=CONTROLLED_OFFSET
    CONTROLLED_OFFSET=seconds
    # Only the guarded ephemeral fixture changes Django's clock. OS/TLS clocks stay unchanged.
    timezone.datetime=ControlledDateTime
    assert abs((timezone.now()-datetime.now(dt_timezone.utc)).total_seconds()-seconds)<1
    return Response({'controlled_seconds':seconds,'production':False})

def traced_verification(function):
    """Identify failed fixture assertions without logging requests or secrets."""
    @wraps(function)
    def wrapped(*args, **kwargs):
        try:
            return function(*args, **kwargs)
        except Exception as error:
            frames=traceback.extract_tb(error.__traceback__)
            locations=[f'{Path(frame.filename).name}:{frame.lineno}:{frame.name}' for frame in frames]
            print('REAL_FIXTURE_FAILED type='+type(error).__name__+' locations='+','.join(locations),flush=True)
            raise
    return wrapped

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
def expired_tokens(request):
    owner_only(request)
    refresh=RefreshToken.for_user(User.objects.get(pk=STATE['jean']))
    past=timezone.now()-timedelta(days=14)
    access=refresh.access_token
    refresh.set_iat(at_time=past);access.set_iat(at_time=past)
    refresh.set_exp(from_time=past,lifetime=timedelta(seconds=1))
    access.set_exp(from_time=past,lifetime=timedelta(seconds=1))
    return Response({'access':str(access),'refresh':str(refresh)})

@api_view(['POST'])
@permission_classes([IsAuthenticated])
@traced_verification
def verify_recovery(request):
    owner_only(request)
    disabled=TerrainSubmission.objects.get(client_operation_id=request.data['disabled_id'])
    recovered=TerrainSubmission.objects.get(client_operation_id=request.data['recovered_id'])
    assert disabled.author_user_id==STATE['jean'] and disabled.outcome.business_status=='CONFIRMED'
    member=User.objects.get(pk=STATE['jean']).memberships.get(exploitation_id=STATE['farm'])
    assert not member.is_active
    assert Client.objects.get(nom='Client Jean désactivé').created_by_id==STATE['jean']
    decision=TerrainDecision.objects.get(submission=disabled)
    assert decision.decision_actor_id==STATE['owner']
    assert recovered.author_user_id==STATE['paul'] and recovered.outcome.business_status=='NEEDS_RECONCILIATION'
    assert not Client.objects.filter(nom='Client Paul récupéré').exists()
    device=DeviceRegistration.objects.get(pk=recovered.device_id)
    assert device.status=='REVOKED' and not device.is_primary_writer
    event=AuditEvent.objects.get(action='TERRAIN_RECOVERED',operation_id=recovered.client_operation_id)
    assert event.actor_user_id==STATE['paul'] and event.decision_actor_id==STATE['owner'] and event.source=='RECOVERY'
    assert TerrainSubmission.objects.count()==20 and not BEARER_ON_DEVICE
    result={'verified':True,'disabled_author':STATE['jean'],'decision_actor':STATE['owner'],
      'recovered_author':STATE['paul'],'revoked':True,'reactivated':False,'recovered_applied':False}
    (EVIDENCE/'server-recovery-verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print('REAL_SERVER_RECOVERY_VERIFIED disabled_author=Jean decision=Owner recovered_author=Paul revoked=true',flush=True)
    return Response(result)

@api_view(['POST'])
@permission_classes([IsAuthenticated])
@traced_verification
def verify_resilience(request):
    owner_only(request)
    assert settings.NATIVE_RESILIENCE
    ids=request.data['operation_ids']
    assert len(ids)==2 and len(set(ids))==2
    rows=list(TerrainSubmission.objects.filter(client_operation_id__in=ids))
    assert len(rows)==2 and TerrainSubmission.objects.count()==2
    assert all(r.author_user_id==STATE['jean'] and r.outcome.business_status=='CONFIRMED' for r in rows)
    assert Client.objects.count()==2
    assert not Client.objects.filter(nom='Client écriture interrompue').exists()
    for action in ['TERRAIN_RECEIVED','TERRAIN_APPLIED']:
        assert AuditEvent.objects.filter(action=action,operation_id__in=ids).count()==2
    assert not BEARER_ON_DEVICE
    result={'verified':True,'originals':2,'effects':2,'author':STATE['jean'],
      'interrupted_write_applied':False,'duplicate_effects':False,'device_bearer':False}
    (EVIDENCE/'server-resilience-verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print('REAL_SERVER_RESILIENCE_VERIFIED originals=2 effects=2 duplicate=false',flush=True)
    return Response(result)

@api_view(['POST'])
@permission_classes([IsAuthenticated])
@traced_verification
def verify_full_journey(request):
    owner_only(request)
    ids=request.data['operation_ids']
    assert len(ids)==9 and len(set(ids))==9
    rows=list(TerrainSubmission.objects.filter(client_operation_id__in=ids).order_by('local_sequence'))
    assert len(rows)==9 and TerrainSubmission.objects.count()==16
    assert [row.author_user_id for row in rows]==[STATE['jean']]*4+[STATE['paul']]*5
    assert all(row.outcome.business_status=='CONFIRMED' for row in rows[:8])
    assert rows[8].outcome.business_status=='NEEDS_RECONCILIATION'
    assert rows[8].outcome.reason_code=='REFERENCE_OUTSIDE_FARM'
    assert Lot.objects.get(pk=STATE['foreign_lot']).stock==9
    expense=Depense.objects.get()
    feed=ConsommationAliment.objects.get()
    weighing=PeseeProduction.objects.get()
    assert str(expense.montant)=='123.45' and expense.created_by_id==STATE['jean']
    assert str(feed.quantite_kg)=='1.234' and feed.depense_id==expense.pk and feed.created_by_id==STATE['jean']
    assert str(weighing.poids_total_kg)=='1.234' and weighing.created_by_id==STATE['jean']
    collection=CollecteOeufs.objects.exclude(pk__in=STATE['collections']).get()
    assert collection.nombre_commercialisable==8 and collection.created_by_id==STATE['jean']
    assert lot_stock_queryset(STATE['farm']).get(pk=STATE['egg_lot']).confirmed_egg_stock==109
    parent=Achat.objects.get().lot
    assert parent.stock==13
    birth=Mouvement.objects.get(type_mouvement='NAISSANCE')
    assert birth.lot_origine_id==parent.pk and birth.quantite==3 and birth.mort_nes==2 and birth.lot.stock==3
    for kind,quantity in [('MORTALITE',2),('DON',1),('VOL',1)]:
        movement=Mouvement.objects.get(type_mouvement=kind)
        assert movement.lot_id==parent.pk and movement.quantite==quantity and movement.created_by_id==STATE['paul']
    assert AuditEvent.objects.filter(action='TERRAIN_RECEIVED',operation_id__in=ids).count()==9
    assert AuditEvent.objects.filter(action='TERRAIN_APPLIED',operation_id__in=ids).count()==8
    assert not BEARER_ON_DEVICE
    result={'verified':True,'operations':9,'parent_stock':13,'newborn_stock':3,'collection_available':8,
      'jean':4,'paul':5,'duplicates':False,'foreign_stock':9,'foreign_reference_applied':False,'egg_stock':109}
    (EVIDENCE/'server-full-journey-verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print('REAL_SERVER_FULL_JOURNEY_VERIFIED operations=9 parent_stock=13 newborn_stock=3 isolation=true authors=Jean+Paul',flush=True)
    return Response(result)

@api_view(['POST'])
@permission_classes([IsAuthenticated])
@traced_verification
def verify_expired_grants(request):
    owner_only(request)
    assert CONTROLLED_OFFSET==345600
    ids=request.data['operation_ids']
    assert len(ids)==2 and len(set(ids))==2
    rows=list(TerrainSubmission.objects.filter(client_operation_id__in=ids).order_by('local_sequence'))
    assert len(rows)==2 and TerrainSubmission.objects.count()==18
    assert [row.author_user_id for row in rows]==[STATE['jean'],STATE['paul']]
    for row in rows:
        assert row.outcome.business_status=='CONFIRMED'
        grant=row.offline_authorization
        assert grant.expires_at<timezone.now()
        assert grant.issued_at<=row.local_recorded_at<=grant.expires_at
        assert row.received_at>grant.expires_at
    assert Client.objects.filter(nom__in=['Client ancien Jean','Client ancien Paul']).count()==2
    assert AuditEvent.objects.filter(action='TERRAIN_APPLIED',operation_id__in=ids).count()==2
    result={'verified':True,'originals':2,'controlled_seconds':CONTROLLED_OFFSET,
      'grants_expired_at_receipt':True,'recorded_in_original_window':True}
    (EVIDENCE/'server-expired-grants-verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print('REAL_SERVER_EXPIRED_GRANTS_VERIFIED originals=2 controlled_days=4 original_windows=true',flush=True)
    return Response(result)

@api_view(['POST'])
@permission_classes([IsAuthenticated])
@traced_verification
def verify(request):
    owner_only(request)
    ids=request.data.get('operation_ids')
    assert isinstance(ids,list) and len(ids)==7 and len(set(ids))==7
    originals=list(TerrainSubmission.objects.filter(client_operation_id__in=ids).order_by('local_sequence'))
    assert len(originals)==7
    assert [r.author_user_id for r in originals]==[STATE['jean']]*6+[STATE['paul']]
    assert all(r.exploitation_id==STATE['farm'] for r in originals)
    assert Achat.objects.count()==1 and Vente.objects.count()==2 and VenteOeufs.objects.count()==1
    egg_sale=VenteOeufs.objects.get()
    assert str(egg_sale.montant_total)=='0.52' and egg_sale.created_by_id==STATE['jean']
    assert egg_sale.vente.created_by_id==STATE['jean'] and str(egg_sale.vente.montant_total)=='0.52'
    sale=Vente.objects.exclude(pk=egg_sale.vente_id).get();assert str(sale.montant_total)=='30000.00'
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
    path('api/test-fixture/advance-clock/',advance_fixture_clock),
    path('api/test-fixture/verify-expired-grants/',verify_expired_grants),
    path('api/test-fixture/expired-tokens/',expired_tokens),
    path('api/test-fixture/verify-recovery/',verify_recovery),
    path('api/test-fixture/verify-resilience/',verify_resilience),
    path('api/test-fixture/verify-full-journey/',verify_full_journey),
    path('api/test-fixture/verify/',verify),path('api/',include('core.urls'))]

def assert_database():
    conf=connection.settings_dict
    assert connection.vendor=='postgresql' and conf['HOST']=='127.0.0.1' and str(conf['PORT'])=='55438'
    expected='elevage_native_i_resilience_test' if settings.NATIVE_RESILIENCE else 'elevage_native_i_test'
    assert conf['NAME']==expected and conf['USER']=='native_i_test'
    with connection.cursor() as cursor:
        cursor.execute('SELECT current_database(),inet_server_port(),version()')
        name,port,version=cursor.fetchone()
        assert name==expected and port==5432 and version.startswith('PostgreSQL 18.4 ')
        cursor.execute("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public'")
        assert cursor.fetchone()[0]==0,'Fresh database required; never reset an existing database'
    print(f'TEST_DATABASE PostgreSQL18.4 host=127.0.0.1:55438 database={expected} production=false',flush=True)

def seed():
    password='SyntheticNativeI-2026-only'
    owner=User.objects.create_user(username='native-owner',password=password)
    farm=owner.exploitation
    farm.offline_policy_enabled=True;farm.save(update_fields=['offline_policy_enabled'])
    jean=User.objects.create_user(username='native-jean',password=password,exploitation=farm)
    paul=User.objects.create_user(username='native-paul',password=password,exploitation=farm)
    species=Espece.objects.create(exploitation=farm,nom='Espèce synthétique native')
    category=CategorieDepense.objects.create(exploitation=farm,nom='Aliment synthétique natif')
    egglot=Lot.objects.create(exploitation=farm,espece=species,nom='Œufs natifs',type_production='OEUFS',date_debut=timezone.localdate())
    at=timezone.now()-timedelta(days=1)
    collections=[]
    for offset,count in [(-120,2),(-60,3),(1,100)]:
        row=CollecteOeufs.objects.create(exploitation=farm,lot=egglot,
          collecte_at=at+timedelta(minutes=offset),nombre_collecte=count,created_by=jean)
        sync_collection_stock_movement(row);collections.append(row.pk)
    task=Task.objects.create(exploitation=farm,title='Visite native réelle',date=timezone.localdate(),assigned_to=jean,status='IN_PROGRESS')
    paul_task=Task.objects.create(exploitation=farm,title='Visite personnelle Paul',date=timezone.localdate(),assigned_to=paul)
    foreign_owner=User.objects.create_user(username='native-foreign-owner',password=password)
    foreign_species=Espece.objects.create(exploitation=foreign_owner.exploitation,nom='Espèce hors exploitation')
    foreign_lot=Lot.objects.create(exploitation=foreign_owner.exploitation,espece=foreign_species,
      nom='Lot hors exploitation',date_debut=timezone.localdate())
    Mouvement.objects.create(exploitation=foreign_owner.exploitation,lot=foreign_lot,type_mouvement='ACHAT',quantite=9)
    STATE.update(owner=owner.pk,farm=farm.pk,jean=jean.pk,paul=paul.pk,species=species.pk,
      jean_membership=jean.memberships.get(exploitation=farm).pk,category=category.pk,
      egg_lot=egglot.pk,egg_sale_at=at.isoformat(),task=task.pk,paul_task=paul_task.pk,
      foreign_lot=foreign_lot.pk,collections=collections)
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
        if settings.NATIVE_RESILIENCE and environ['PATH_INFO']=='/api/offline/submissions/' and not STATE.get('held_once'):
            captured=[]
            response=app(environ,lambda status,headers,exc_info=None:captured.append((status,headers,exc_info)))
            chunks=list(response)
            try:
                assert captured[0][0].startswith('200')
                assert TerrainSubmission.objects.count()==2
                STATE['held_once']=True
                print('REAL_SYNC_CRASH_SERVER_PERSISTED originals=2',flush=True)
                threading.Event().wait(90)
                start_response(*captured[0]);return chunks
            finally:response.close()
        return app(environ,start_response)
    port=9444 if settings.NATIVE_RESILIENCE else 9443
    server=make_server('127.0.0.1',port,inspected,server_class=ThreadedServer,handler_class=QuietHandler)
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(private/'server.pem',private/'key.pem')
    server.socket=context.wrap_socket(server.socket,server_side=True)
    (private/'ready').write_text('READY\n')
    print(f'REAL_NATIVE_TEST_SERVER_READY https://10.0.2.2:{port}/api production=false',flush=True)
    server.serve_forever()

if __name__=='__main__':main()
