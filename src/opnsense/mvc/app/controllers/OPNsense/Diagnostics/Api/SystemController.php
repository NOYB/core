<?php

/*
 * Copyright (C) 2022 Deciso B.V.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 * OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

namespace OPNsense\Diagnostics\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Config;
use OPNsense\Core\Backend;

/**
 * Class SystemController
 * @package OPNsense\Diagnostics\Api
 */
class SystemController extends ApiControllerBase
{
    private function formatUptime($uptime)
    {
        $days = floor($uptime / (3600 * 24));
        $hours = floor(($uptime % (3600 * 24)) / 3600);
        $minutes = floor(($uptime % 3600) / 60);
        $seconds = $uptime % 60;

        if ($days > 0) {
            $plural = $days > 1 ? gettext("days") : gettext("day");
            return sprintf(
                "%d %s, %02d:%02d:%02d",
                $days,
                $plural,
                $hours,
                $minutes,
                $seconds
            );
        } else {
            return sprintf("%02d:%02d:%02d", $hours, $minutes, $seconds);
        }
    }

    public function memoryAction()
    {
        $data = json_decode((new Backend())->configdRun('system show vmstat_mem'), true);
        if (empty($data) || !is_array($data)) {
            return [];
        }
        if (!empty($data['malloc-statistics']) && !empty($data['malloc-statistics']['memory'])) {
            $data['malloc-statistics']['totals'] = ['used' => 0];
            foreach ($data['malloc-statistics']['memory'] as &$item) {
                $item['name'] = $item['type'];
                unset($item['type']);
                $data['malloc-statistics']['totals']['used'] += $item['memory-use'];
            }
            $tmp = number_format($data['malloc-statistics']['totals']['used']) . " k";
            $data['malloc-statistics']['totals']['used_fmt'] = $tmp;
        }
        if (!empty($data['memory-zone-statistics']) && !empty($data['memory-zone-statistics']['zone'])) {
            $data['memory-zone-statistics']['totals'] = ['used' => 0];
            foreach ($data['memory-zone-statistics']['zone'] as $item) {
                $data['memory-zone-statistics']['totals']['used'] += $item['used'];
            }
            $tmp = number_format($data['memory-zone-statistics']['totals']['used']) . " k";
            $data['memory-zone-statistics']['totals']['used_fmt'] = $tmp;
        }
        return $data;
    }

    public function systemInformationAction()
    {
        $config = Config::getInstance()->object();
        $backend = new Backend();

        $product = json_decode($backend->configdRun('firmware product'), true);
        $current = explode('_', $product['product_version'])[0];
        /* information from changelog, more accurate for production release */
        $from_changelog = strpos($product['product_id'], '-devel') === false &&
            !empty($product['product_latest']) &&
            $product['product_latest'] != $current;

        /* update status from last check, also includes major releases */
        $from_check = !empty($product['product_check']['upgrade_sets']) ||
            !empty($product['product_check']['downgrade_packages']) ||
            !empty($product['product_check']['new_packages']) ||
            !empty($product['product_check']['reinstall_packages']) ||
            !empty($product['product_check']['remove_packages']) ||
            !empty($product['product_check']['upgrade_packages']);

        $versions = [
            sprintf('%s %s', $product['product_name'], $product['product_version'], $product['product_arch']),
            php_uname('s') . ' ' . php_uname('r'),
            trim($backend->configdRun('system openssl version')),
        ];

        if (!empty($product['product_license']['valid_to'])) {
            $versions[] = sprintf(gettext('Licensed until %s'), $product['product_license']['valid_to']);
        }

        $response = [
            'name' => $config->system->hostname . '.' . $config->system->domain,
            'versions' => $versions,
            'updates' => ($from_changelog || $from_check)
                ? gettext('Click to view pending updates.')
                : gettext('Click to check for updates.'),
        ];

        return $response;
    }

    public function systemTimeAction()
    {
        $config = Config::getInstance()->object();
        $boottime = json_decode((new Backend())->configdRun('system sysctl values kern.boottime,vm.loadavg'), true);
        preg_match("/sec = (\d+)/", $boottime['kern.boottime'], $matches);

        $last_change = date("D M j G:i:s T Y", !empty($config->revision->time) ? intval($config->revision->time) : 0);
        $loadavg = explode(' ', $boottime['vm.loadavg']);
        if (count($loadavg) == 5 && $loadavg[0] == '{' && $loadavg[4] == '}') {
            $loadavg = join(', ', [$loadavg[1], $loadavg[2], $loadavg[3]]);
        } else {
            $loadavg = gettext('N/A');
        }

        $response = [
            'uptime' => $this->formatUptime(time() - $matches[1]),
            'boottime' => date("D M j G:i:s T Y", $matches[1]),
            'datetime' => date("D M j G:i:s T Y"),
            'boottime' => date("D M j G:i:s T Y", $matches[1]),
            'config' => $last_change,
            'loadavg' => $loadavg,
        ];

        return $response;
    }

    public function systemResourcesAction()
    {
        $result = [];

        $mem = json_decode((new Backend())->configdpRun('system sysctl values', implode(',', [
            'hw.physmem',
            'vm.stats.vm.v_page_count',
            'vm.stats.vm.v_inactive_count',
            'vm.stats.vm.v_cache_count',
            'vm.stats.vm.v_free_count',
            'kstat.zfs.misc.arcstats.size'
        ])), true);

        if (!empty($mem['vm.stats.vm.v_page_count'])) {
            $pc = $mem['vm.stats.vm.v_page_count'];
            $ic = $mem['vm.stats.vm.v_inactive_count'];
            $cc = $mem['vm.stats.vm.v_cache_count'];
            $fc = $mem['vm.stats.vm.v_free_count'];
            $result['memory']['total'] = $mem['hw.physmem'];
            $result['memory']['total_frmt'] = sprintf('%d', $mem['hw.physmem'] / 1024 / 1024);
            $result['memory']['used'] = round(((($pc - ($ic + $cc + $fc))) / $pc) * $mem['hw.physmem'], 0);
            $result['memory']['used_frmt'] = sprintf('%d', $result['memory']['used'] / 1024 / 1024);
            if (!empty($mem['kstat.zfs.misc.arcstats.size'])) {
                $arc_size = $mem['kstat.zfs.misc.arcstats.size'];
                $result['memory']['arc'] = $arc_size;
                $result['memory']['arc_frmt'] = sprintf('%d', $arc_size / 1024 / 1024);
                $result['memory']['arc_txt'] = sprintf(gettext('ARC size %d MB'), $arc_size / 1024 / 1024);
            }
        } else {
            $result['memory']['used'] = gettext('N/A');
        }

        return $result;
    }

    public function systemDiskAction()
    {
        $result = [];

        $disk_info = json_decode((new Backend())->configdRun('system diag disk'), true);

        if (!empty($disk_info['storage-system-information'])) {
            foreach ($disk_info['storage-system-information']['filesystem'] as $fs) {
                if (!in_array(trim($fs['type']), ['cd9660', 'msdosfs', 'tmpfs', 'ufs', 'zfs'])) {
                    continue;
                }

                $result['devices'][] = [
                    'device' => $fs['name'],
                    'type' => trim($fs['type']),
                    'blocks' => $fs['blocks'],
                    'used' => $fs['used'],
                    'available' => $fs['available'],
                    'used_pct' => $fs['used-percent'],
                    'mountpoint' => $fs['mounted-on'],
                ];
            }
        }

        return $result;
    }

    public function systemMbufAction()
    {
        return json_decode((new Backend())->configdRun('system show mbuf'), true);
    }

    public function systemSwapAction()
    {
        return json_decode((new Backend())->configdRun('system show swapinfo'), true);
    }

    public function systemTemperatureAction()
    {
        # Save/retrieve file instead of reconstructing sensors from backend every time.
        $SYSCTLS_FILE = '/tmp/SYSCTLS_Thermal_Sensors_Widget';
        if (time()-filemtime($SYSCTLS_FILE) > 24 * 3600) {
            $backend = new Backend();

            /* derive temperature sensors */
            $sensors = trim($backend->configdRun('system sensors'));
            $sensors .= "\n" . 'kern.smp.threads_per_core';
            file_put_contents($SYSCTLS_FILE, $sensors);
        }

        /* read temperatures individually from previously derived sensors */
        $sensors = str_replace("\n", ' ', file_get_contents($SYSCTLS_FILE));
        sleep(1); # avoid probe affecting measured temperature values
        $temps = $this->shellCmd('sysctl -i ' . $sensors);

        /* indexed to associative array */
        foreach($temps as $tmp) {
            $tmp = explode(':', $tmp);
            $temps_tmp[$tmp[0]] = $tmp[1];
        }
        $temps = $temps_tmp;

        $result = [];
        foreach ($temps as $name => $value) {
            /* Return only one "cpu" (thread) temperature per core if hyper-thread enabled. */
            /* i.e. multiple threads per core. */
            if ($temps['kern.smp.threads_per_core'] >= 2 && str_contains($name, 'dev')) {
                preg_match_all("/.*\.([0-9]+)\.temperature.*/", $name, $thread);
                if ($thread[1][0] % $temps['kern.smp.threads_per_core'] != 0) {
                    continue;
                }
            }

            $tempItem = [];
            $tempItem['device'] = $name;
            $tempItem['device_seq'] = (int)filter_var($tempItem['device'], FILTER_SANITIZE_NUMBER_INT);
            $tempItem['temperature'] = trim(str_replace('C', '', $value));
            $tempItem['type_translated'] = gettext('Other');
            $tempItem['type'] = 'other';

            /* try to categorize a few of the readings just for labels */
            if (str_starts_with($tempItem['device'], 'hw.acpi.')) {
                $tempItem['type_translated'] = gettext('Zone');
                $tempItem['type'] = 'zone';
            } elseif (str_starts_with($tempItem['device'], 'dev.amdtemp.')) {
                $tempItem['type_translated'] = gettext('AMD');
                $tempItem['type'] = 'amd';
            } elseif (str_starts_with($tempItem['device'], 'dev.pchtherm.')) {
                $tempItem['type_translated'] = gettext('Platform');
                $tempItem['type'] = 'platform';
            } elseif (str_starts_with($tempItem['device'], 'dev.cpu.')) {
                $tempItem['type_translated'] = gettext('CPU');
                $tempItem['type'] = 'cpu';
            }

            if (str_contains($name, 'threads_per_core')) {
                $tempItem['threads_per_core'] = trim($value);
                $tempItem['type'] = 'threads_per_core';
                $tempItem['temperature'] = '';
                $tempItem['type_translated'] = '';
            }

            $result[] = $tempItem;
        }
/**
        # Return only one "cpu" (thread) temperature per core if hyper-thread enabled.  i.e. multiple threads per core.
        if ($threads_per_core >= 1) {
            $type = array('core', gettext('Core'));
            $threads_per = $threads_per_core;
        } else {
            $type = array('cpu', gettext('CPU'));
            $threads_per = 1; // TODO: Set according to the CPU's Hyper-Threading (threads_per_cpu)
        }

        foreach ($result as $key => $tempItem) {
            if ($result[$key]['type'] == 'cpu') {
                if ($result[$key]['device_seq'] % $threads_per == 0) {
                    $result[$key]['device_seq'] = $result[$key]['device_seq'] / $threads_per;
                    $result[$key]['type'] = $type[0];
                    $result[$key]['type_translated'] = $type[1];
                } else {
                   unset($result[$key]);
                }
            }

            elseif ($result[$key]['type'] == 'zone') {
                if (($result[$key]['temperature'] < 11) || ($result[$key]['temperature'] == 27.9)) {
                    unset($result[$key]);
                }
            }

            elseif ($result[$key]['type'] == 'threads_per_core') {
                unset($result[$key]);
            }
        }

        return array_values($result);
/**/
        return $result;
    }

    public function shellCmd(string $cmd)
    {
        exec($cmd . '  2>&1', $payload, $returncode);
        if ($returncode == 0 && !empty($payload[0])) {
            return $payload;
        }
        return [];
    }

}
