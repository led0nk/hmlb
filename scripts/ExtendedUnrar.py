#!/usr/bin/env python3
"""
ExtendedUnrar post-processing script for NZBGet

Copyright (C) 2023 h0tw1r3
Copyright (C) 2014 thorli <thor78@gmx.at>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

Version 1.0 (2014-06-01)
Version 2.0 (2019-04-20) Fixes/improvements/cleanup by Bun
"""

##############################################################################
### NZBGET POST-PROCESSING SCRIPT                                          ###

# Unrar nested rar files
#
# This script extracts nested rar archives from downloaded files.
#
# NOTE: This script requires Python 3 to be installed on your system.

##############################################################################
### OPTIONS                                                                ###

# Full Path to Unrar executable (optional)
#
# (if blank, NZBGet "UnrarCmd" setting is used)
#UnrarPath=

# File extension of rar files to search for (default: *.[rR]??)
#
# Use "*" and "?" for wildcards and "[]" for character ranges.
# NOTE: This is a filesystem glob, NOT REGEX!
#RarExtensions=*.[rR]??

# Time (in seconds) to pause start of script (default: 5)
#
# Gives NZBGet time to perform "UnpackCleanupDisk" action on slow systems
#WaitTime=5

# Delete leftover extended rar files after successful extract (yes, no).
#
#DeleteLeftover=yes

### NZBGET POST-PROCESSING SCRIPT                                          ###
##############################################################################


import os
import sys
import subprocess
import time
from shlex import quote
from pathlib import Path

# Exit codes used by NZBGet
POSTPROCESS_SUCCESS=93
POSTPROCESS_ERROR=94
POSTPROCESS_NONE=95

# Check if the script is called from nzbget 18.0 or later
if not 'NZBOP_EXTENSIONS' in os.environ:
    print('This script requires NZBGet v18.0 or later', file=sys.stderr)
    sys.exit(POSTPROCESS_ERROR)

# Check nzbget.conf options
required_environment = (
        'NZBOP_UNRARCMD',
        'NZBPO_UNRARPATH',
        'NZBPO_RAREXTENSIONS',
        'NZBPO_WAITTIME',
        'NZBPO_DELETELEFTOVER'
        )
for optname in required_environment:
    if not optname in os.environ:
        print(f'Option "{optname[6:]}" is missing in NZBGet configuration', file=sys.stderr)
        sys.exit(POSTPROCESS_ERROR)

# If NZBGet Unpack setting isn't enabled, this script cannot work properly
if os.environ['NZBOP_UNPACK'] != 'yes':
    print('Option "Unpack" must be enabled in NZBGet configuration', file=sys.stderr)
    sys.exit(POSTPROCESS_ERROR)

unrarpath = os.environ['NZBPO_UNRARPATH']
rarext = os.environ['NZBPO_RAREXTENSIONS']
waittime = os.environ['NZBPO_WAITTIME']
deleteleftover = os.environ['NZBPO_DELETELEFTOVER']

if unrarpath == '':
    unrarpath=os.environ['NZBOP_UNRARCMD']

# Check TOTALSTATUS
if os.environ['NZBPP_TOTALSTATUS'] != 'SUCCESS':
    print('NZBGet download TOTALSTATUS is not SUCCESS, exiting', file=sys.stderr)
    sys.exit(POSTPROCESS_NONE)

# Check if destination directory exists (important for reprocessing of history items)
if not os.path.isdir(os.environ['NZBPP_DIRECTORY']):
    print(f'Destination directory {os.environ["NZBPP_DIRECTORY"]} ' \
           'does not exist, exiting', file=sys.stderr)
    sys.exit(POSTPROCESS_NONE)

# Sleep (maybe)
if os.environ['NZBOP_UNPACKCLEANUPDISK'] == 'yes':
    print(f'Sleeping {waittime} seconds to give NZBGet time to finish ' \
           'UnpackCleanupDisk action', flush=True)
    time.sleep(int(float(waittime)))

EXIT_STATUS = POSTPROCESS_SUCCESS

os.chdir(os.environ['NZBPP_DIRECTORY'])
for dirpath, dirnames, filenames in os.walk('.'):
    all_rar_files = [name for name in filenames if Path(name).match(rarext)]
    all_rar_archives = [
            name for name in all_rar_files
            if os.path.splitext(name)[1].lower() == '.rar'
            ]
    print(f'Found {len(all_rar_archives)} rar archives')
    for rar in all_rar_archives:
        print(f'Extracting {rar}', flush=True)
        sys.stdout.flush()
        cmdline = f'{unrarpath} e -idcp -ai -ierr -o- ' + quote(rar)
        result = subprocess.run(cmdline, shell=True, capture_output=True, text=True, check=False)
        if result.returncode == 0:
            if deleteleftover == 'yes':
                rar_barename = os.path.splitext(rar)[0]
                rar_files = [name for name in all_rar_files
                        if os.path.splitext(name)[0] == rar_barename
                        ]
                print(f'Deleting {len(rar_files)} leftover rar files', flush=True)
                for name in rar_files:
                    try:
                        os.remove(name)
                    except OSError as e:
                        print(f'Failed to delete {name}: {e}', file=sys.stderr)
                        EXIT_STATUS = POSTPROCESS_NONE
        else:
            print(f'Extract failed, return code {result.returncode}', file=sys.stderr)
            print('\n'.join((filter(None, result.stderr.split('\n')))), file=sys.stderr)
            EXIT_STATUS = POSTPROCESS_NONE

sys.exit(EXIT_STATUS)
