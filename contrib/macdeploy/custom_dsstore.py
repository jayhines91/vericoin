#!/usr/bin/env python3
# Copyright (c) 2013-2018 The Bitcoin Core developers
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
import sys
from ds_store import DSStore

output_file = sys.argv[1]
package_name_ns = sys.argv[2]

ds = DSStore.open(output_file, 'w+')
ds['.']['bwsp'] = {
    'ShowStatusBar': False,
    'WindowBounds': '{{300, 280}, {500, 343}}',
    'ContainerShowSidebar': False,
    'SidebarWidth': 0,
    'ShowTabView': False,
    'PreviewPaneVisibility': False,
    'ShowToolbar': False,
    'ShowSidebar': False,
    'ShowPathbar': True
}

icvp = {
    'gridOffsetX': 0.0,
    'textSize': 12.0,
    'viewOptionsVersion': 1,
    'backgroundColorBlue': 1.0,
    'iconSize': 96.0,
    'backgroundColorGreen': 1.0,
    'arrangeBy': 'none',
    'showIconPreview': True,
    'gridSpacing': 100.0,
    'gridOffsetY': 0.0,
    'showItemInfo': False,
    'labelOnBottom': True,
    'backgroundType': 1,
    'backgroundColorRed': 1.0
}
ds['.']['icvp'] = icvp

ds['.']['vSrn'] = ('long', 1)

ds['Applications']['Iloc'] = (370, 156)
ds['Vericoin.app']['Iloc'] = (128, 156)

ds.flush()
ds.close()