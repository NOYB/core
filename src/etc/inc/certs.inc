<?php

/*
 * Copyright (C) 2008 Shrew Soft Inc. <mgrooms@shrew.net>
 * Copyright (C) 2010 Jim Pingle <jimp@pfsense.org>
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


function &lookup_ca($refid)
{
    global $config;

    if (is_array($config['ca'])) {
        foreach ($config['ca'] as & $ca) {
            if ($ca['refid'] == $refid) {
                return $ca;
            }
        }
    }

    $false = false;
    return $false;
}

function &lookup_ca_by_subject($subject)
{
    global $config;

    if (is_array($config['ca'])) {
        foreach ($config['ca'] as & $ca) {
            $ca_subject = cert_get_subject($ca['crt']);
            if ($ca_subject == $subject) {
                return $ca;
            }
        }
    }

    return false;
}

function &lookup_cert($refid)
{
    global $config;

    if (is_array($config['cert'])) {
        foreach ($config['cert'] as & $cert) {
            if ($cert['refid'] == $refid) {
                return $cert;
            }
        }
    }

    return false;
}

function &lookup_crl($refid)
{
    global $config;

    if (is_array($config['crl'])) {
        foreach ($config['crl'] as & $crl) {
            if ($crl['refid'] == $refid) {
                return $crl;
            }
        }
    }

    return false;
}

function ca_chain_array(&$cert)
{
    if ($cert['caref']) {
        $chain = array();
        $crt = lookup_ca($cert['caref']);
        if (!$crt) {
            return false;
        }
        $chain[] = $crt;
        while ($crt) {
            $caref = isset($crt['caref']) ? $crt['caref'] : false;
            if ($caref) {
                $crt = lookup_ca($caref);
            } else {
                $crt = false;
            }
            if ($crt) {
                if (in_array($crt, $chain)) {
                    break; /* exit endless loop */
                }
                $chain[] = $crt;
            }
        }
        return $chain;
    }
    return false;
}

function ca_chain(&$cert)
{
    $ca = '';
    if (!isset($cert['caref'])) {
        return $ca;
    }

    $cas = ca_chain_array($cert);
    if (!is_array($cas)) {
        return $ca;
    }

    foreach ($cas as &$ca_cert) {
        $ca .= base64_decode($ca_cert['crt']);
        $ca .= "\n";
    }

    /* sanitise output to make sure we generate clean files */
    return str_replace("\n\n", "\n", str_replace("\r", "", $ca));
}


// Add cert trust file for specified CA cert, if add and trusted.  Otherwise remove cert trust file if exists.
function ca_trusted_cert_add_rmv($id, $add, &$ca_certfile = '') {
    global $config;

    $ca_dir = getenv('SSL_CERT_DIR') ?: (ini_get('openssl.capath') ?: '/etc/ssl/certs');
    $ca_hash = openssl_x509_parse(base64_decode($config['ca'][$id]['crt']))['hash'];
    $ca_certfile = "$ca_dir/$ca_hash.0";

    if ($add && isset($config['ca'][$id]['trusted'])) {

        $cert_data = cert_get_config_meta_data($id) . cert_get_data($config['ca'][$id]['crt']);

        // Check for missing or corrupt cert file.  Not malicious tampering.  A malicious actor would already have root privileges with access to the entire certs bundle as well as all files on the system.
        if (@hash_file('md5', $ca_certfile) !== @hash('md5', $cert_data)) {
            if (!file_exists($ca_dir)) {
                @mkdir($ca_dir, 0755);
            }
            if (@file_put_contents($ca_certfile, $cert_data) === false) {
                log_error(gettext("Error: cannot write $ca_certfile file in ca_trusted_cert_add_rmv()."));
                return false;
            }
        }
    } else {
        return ca_trusted_cert_remove_by_name($ca_certfile, 'ca_trusted_cert_add_rmv()');
    }

    return true;
}

// Synchronize cert trust files with config CA certs.
function ca_trusted_certs_synchronize() {
    global $config;

    $ca_dir = getenv('SSL_CERT_DIR') ?: (ini_get('openssl.capath') ?: '/etc/ssl/certs');

    $res = true;

    // Add missing cert trust files for CA certs in config that are trusted, and remove cert trust files of CA certs in config that are not trusted.
    // Get list of trust files for CA certs from config.
    if (is_array($config['ca'])) {
        $add = true;
        foreach($config['ca'] as $id => $ca) {
            $res &= ca_trusted_cert_add_rmv($id, $add, $ca_certfile);
            $ca_certfiles[] = $ca_certfile;
        }
    } else {
        $ca_certfiles = array();
    }

    // Remove cert trust files that have no corresponding CA cert in config.  Leave symlinks and directories in place to allow trusted certs to also be added outside the certificate manager.
    foreach (glob("$ca_dir/*") as $ca_certfile) {
        if (!in_array($ca_certfile, $ca_certfiles) && !is_link($ca_certfile) && !is_dir($ca_certfile)) {
            $res &= ca_trusted_cert_remove_by_name($ca_certfile, 'ca_trusted_certs_synchronize()');
        }
    }

    return $res;
}

// Remove cert trust file by name.
function ca_trusted_cert_remove_by_name($ca_certfile, $caller) {
    @unlink($ca_certfile);
    if (file_exists($ca_certfile)) {
        log_error(sprintf(gettext("Error: cannot unlink %s file in %s."), $ca_certfile, $caller));
        return false;
    }
    return true;
}

// Get config cert meta data (Reference ID and Description).
function cert_get_config_meta_data($id) {
    global $config;

    $config_cert_meta_data  = "Config Info:\n";
    $config_cert_meta_data .= "    Reference ID: {$config['ca'][$id]['refid']}\n";
    $config_cert_meta_data .= "    Description: {$config['ca'][$id]['descr']}\n\n";

    return $config_cert_meta_data;
}

// Get CA cert meta data and string.
function cert_get_data($crt) {

    // Export cert with meta data.
    $crt_str = base64_decode($crt);
    openssl_x509_export($crt_str, $crt_text, false);

    // Get the cert fingerprint and include it in the text export.
    $SA = "SHA1";
    $fingerprint = openssl_x509_fingerprint($crt_str, $SA, false);
    $fingerprint = hex_str_octets_delimit($fingerprint, ':', '', '');
    $crt_text = str_replace('-----BEGIN CERTIFICATE-----', $SA.' Fingerprint='.strtoupper($fingerprint)."\n".'-----BEGIN CERTIFICATE-----', $crt_text);

    return $crt_text;
}

// Put a hex string into delimited octets.
function hex_str_octets_delimit($hex_str, $delimiter = ':', $width = null, $indent = '') {
    for ($i=0, $j=strlen($hex_str); $i < $j; $i+=2) {
        if ($width && ($i % ($width*2) == 0)) {
            $hex_strx .= "\n" . $indent;
        }
        $hex_strx .= $hex_str[$i] . $hex_str[$i+1] . $delimiter;
    }
    return trim($hex_strx, $delimiter . ' ');
}


function cert_import(&$cert, $crt_str, $key_str)
{
    $cert['crt'] = base64_encode($crt_str);
    $cert['prv'] = base64_encode($key_str);

    $subject = cert_get_subject($crt_str, false);
    $issuer = cert_get_issuer($crt_str, false);

    // Find my issuer unless self-signed
    if ($issuer != $subject) {
        $issuer_crt =& lookup_ca_by_subject($issuer);
        if ($issuer_crt) {
            $cert['caref'] = $issuer_crt['refid'];
        }
    }
    return true;
}


function certs_build_name($dn)
{
    if (empty($dn) || !is_array($dn)) {
        return 'unknown';
    }

    $subject = '';
    ksort($dn);

    foreach ($dn as $a => $v) {
        if (is_array($v)) {
            ksort($v);
            foreach ($v as $w) {
                $subject = strlen($subject) ? "{$a}={$w}, {$subject}" : "{$a}={$w}";
            }
        } else {
            $subject = strlen($subject) ? "{$a}={$v}, {$subject}" : "{$a}={$v}";
        }
    }

    return $subject;
}


function cert_get_subject($str_crt, $decode = true)
{
    if ($decode) {
        $str_crt = base64_decode($str_crt);
    }

    $inf_crt = openssl_x509_parse($str_crt);
    $components = $inf_crt['subject'];

    return certs_build_name($components);
}

function cert_get_issuer($str_crt, $decode = true)
{
    if ($decode) {
        $str_crt = base64_decode($str_crt);
    }

    $inf_crt = openssl_x509_parse($str_crt);
    $components = $inf_crt['issuer'];

    return certs_build_name($components);
}

/* this function works on x509 (crt), rsa key (prv), and req(csr) */
function cert_get_modulus($str_crt, $decode = true, $type = 'crt')
{
    $type_list = array('crt', 'prv', 'csr');
    $type_cmd = array('x509', 'rsa', 'req');
    $modulus = '';

    if ($decode) {
        $str_crt = base64_decode($str_crt);
    }

    if (in_array($type, $type_list)) {
        $type = str_replace($type_list, $type_cmd, $type);
        $modulus = exec(sprintf(
            'echo %s | /usr/local/bin/openssl %s -noout -modulus',
            escapeshellarg($str_crt),
            escapeshellarg($type)
        ));
    }

    return $modulus;
}


function cert_get_purpose($str_crt, $decode = true)
{
    if ($decode) {
        $str_crt = base64_decode($str_crt);
    }

    $crt_details = openssl_x509_parse($str_crt);
    $purpose = array();
    foreach (['basicConstraints', 'extendedKeyUsage', 'keyUsage', 'authorityInfoAccess'] as $ext) {
        $purpose[$ext] = [];
        if (!empty($crt_details['extensions'][$ext])) {
            foreach (explode(",", $crt_details['extensions'][$ext]) as $item) {
                $purpose[$ext][] = trim($item);
            }
        }
    }
    $purpose['ca'] = in_array('CA:TRUE', $purpose['basicConstraints']) ? 'Yes' : 'No';
    $purpose['server'] = in_array('TLS Web Server Authentication', $purpose['extendedKeyUsage']) ? 'Yes' : 'No';
    // rfc3280 extended key usage
    if (
        in_array('TLS Web Server Authentication', $purpose['extendedKeyUsage']) &&
        in_array('Digital Signature', $purpose['keyUsage']) && (
            in_array('Key Encipherment', $purpose['keyUsage']) ||
            in_array('Key Agreement', $purpose['keyUsage'])
        )
    ) {
        $purpose['id-kp-serverAuth'] = 'Yes';
    } else {
        $purpose['id-kp-serverAuth'] = 'No';
    }
    return $purpose;
}

function cert_get_serial($str_crt, $decode = true)
{
    if ($decode) {
        $str_crt = base64_decode($str_crt);
    }
    $crt_details = openssl_x509_parse($str_crt);
    if (isset($crt_details['serialNumber']) && !empty($crt_details['serialNumber'])) {
        return $crt_details['serialNumber'];
    } else {
        return null;
    }
}

function cert_in_use($certref)
{
    foreach (OPNsense\Core\Config::getInstance()->object()->xpath("//*[text() = '{$certref}']") as $node) {
        $referring_node = $node->xpath("..")[0];
        if ($referring_node->getName() != 'cert') {
            return true;
        }
    }
    return false;
}

/* Compare two certificates to see if they match. */
function cert_compare($cert1, $cert2)
{
    /* Ensure two certs are identical by first checking that their issuers match, then
      subjects, then serial numbers, and finally the moduli. Anything less strict
      could accidentally count two similar, but different, certificates as
      being identical. */
    $c1 = base64_decode($cert1['crt']);
    $c2 = base64_decode($cert2['crt']);
    if (
        (cert_get_issuer($c1, false) == cert_get_issuer($c2, false))
        && (cert_get_subject($c1, false) == cert_get_subject($c2, false))
        && (cert_get_serial($c1, false) == cert_get_serial($c2, false))
        && (cert_get_modulus($c1, false) == cert_get_modulus($c2, false))
    ) {
        return true;
    } else {
        return false;
    }
}

function is_cert_revoked($cert, $crlref = "")
{
    global $config;
    if (!isset($config['crl']) || !is_array($config['crl'])) {
        return false;
    }

    if (!empty($crlref)) {
        $crl = lookup_crl($crlref);
        if (!isset($crl['cert']) || !is_array($crl['cert'])) {
            return false;
        }
        foreach ($crl['cert'] as $rcert) {
            if (cert_compare($rcert, $cert)) {
                return true;
            }
        }
    } else {
        foreach ($config['crl'] as $crl) {
            if (!is_array($crl['cert'])) {
                continue;
            }
            foreach ($crl['cert'] as $rcert) {
                if (cert_compare($rcert, $cert)) {
                    return true;
                }
            }
        }
    }
    return false;
}
