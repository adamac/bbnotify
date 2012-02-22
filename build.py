#!/usr/bin/python
import os
import sys

BASENAME = 'bbnotify'

def run(cmd):
    print cmd
    os.system(cmd)

target = "air"
if len(sys.argv) > 1:
    target = sys.argv[1]

if target == 'air':
    target = 'air %s.air' % BASENAME
elif target == 'native':
    if os.uname()[0] == 'Darwin':
        target = 'native %s.dmg' % BASENAME
    elif os.uname()[0] == 'Windows':
        target = 'native %s.exe' % BASENAME
    elif os.uname()[0] == 'Linux':
        target = 'native %s.rpm' % BASENAME

debug = ''
if len(sys.argv) > 2:
    debug = sys.argv[2]

if debug == 'debug':
    debug='-debug=false -omit-trace-statements=false'

run('amxmlc ' +
    '-library-path+=as3-rpclib.swc ' +
    debug + ' bbnotify.mxml')

run('adt -package -storetype pkcs12 -keystore sampleCert.pfx -target %s bbnotify-app.xml bbnotify.swf red_128.png yellow_128.png green_128.png gray_128.png' % (target))

# Test app
#adl bbnotify-app.xml

# Generate cert
#adt -certificate -cn SelfSigned 1024-RSA sampleCert.pfx dummy

