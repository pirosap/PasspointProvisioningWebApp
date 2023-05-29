#!/usr/bin/perl
#
# Passpoint Provisioning Tools
#  Simple CGI script for Passpoint profile provisioning
#  Target: iOS/iPadOS 14+, macOS 10+
#
# Usage:
#  - Customize the configuration part below.
#  - Put this script on a web server as a CGI program.
#    (Please refer to the HTTP server's manual for configuring CGI.)
#  - Access https://<path_to_script>/passpoint.mobileconfig.
# Notes:
#  - It is recommended to sign the configuration profile (XML), although
#    unsigned profiles can still be used.
#  - External command "openssl" is needed for the signing.
#  - The key and certificate files for signing need to be accessible
#    from the process group such as "www". (chgrp & chmod o+r)
# References:
#  - Configuration Profile Reference
#    https://developer.apple.com/business/documentation/Configuration-Profile-Reference.pdf
#
# 20220723 Hideaki Goto (Cityroam/eduroam)
# 20220729 Hideaki Goto (Cityroam/eduroam)
# 20220805 Hideaki Goto (Cityroam/eduroam)      + expiration date
# 20220812 Hideaki Goto (Cityroam/eduroam)
# 20220817 Hideaki Goto (Cityroam/eduroam)      + cert. chain for signing
# 20220826 Hideaki Goto (Cityroam/eduroam)      + per-user ExpirationDate

use CGI;
use DateTime;
use MIME::Base64;
use Data::UUID;

#---- Configuration part ----

# include common settings
require '/home/computercenter/PPWP/helper//pp-common.cfg';

#### Add your own code here to set ID/PW. ####
my ($userID, $passwd) = @ARGV;

# External code that sets $userID, $passwd, and optionally $ExpirationDate
#require '../etc/getuserinfo.pl';
#if (&getuserinfo($ENV{'REMOTE_USER'})) {
#    exit(1);
#}

my $uname   = $anonID = $userID;
$anonID =~ s/^.*@/anonymous@/;

# To omit signing, uncomment this.
#$signercert  = '';
#$signerchain = '';

#---- Profile composition part ----
# (no need to edit below, hopefully)

my $ts   = DateTime->now->datetime . "Z";

my $uuid1 = Data::UUID->new->create_str();
$uuid1 = uc $uuid1;
my $uuid2 = Data::UUID->new->create_str();
$uuid2 = uc $uuid2;

my $xml_Expire = '';
if ($ExpirationDate ne '') {
    $xml_Expire = <<"EOS";
        <key>RemovalDate</key>
        <date>$ExpirationDate</date>
EOS
}

$RCOI =~ s/\s*//g;
my $xml_RCOI = '';
if ($RCOI ne '') {
    $RCOI = uc $RCOI;
    my @ois = split(/,/, $RCOI);
    $xml_RCOI .= "\t\t\t<key>RoamingConsortiumOIs</key>\n";
    $xml_RCOI .= "\t\t\t<array>\n";
    for my $oi (@ois) {
        $xml_RCOI .= "\t\t\t\t<string>$oi</string>\n";
    }
    $xml_RCOI .= "\t\t\t</array>\n";
}

my $xml_NAI = '';
if ($NAIrealm ne '') {
    $xml_NAI = <<"EOS";
                        <key>NAIRealmNames</key>
                        <array>
                                <string>$NAIrealm</string>
                        </array>
EOS
}

my $xml_anchor = '';
my $xml_cert   = '';
if ($ICAfile ne '') {
    $cert = '';
    open my $fh, '<', $ICAfile;
    while (<$fh>) {
        if (/BEGIN\s+CERTIFICATE/) { next; }
        if (/END\s+CERTIFICATE/)   { last; }
        $cert .= $_;
    }
    close $fh;
    chomp $cert;
    $cert =~ s/[\r\n]//g;

    $xml_anchor = <<"EOS";
                                <key>PayloadCertificateAnchorUUID</key>
                                <array>
                                        <string>$uuid2</string>
                                </array>
EOS

    $xml_cert = <<"EOS";
                <dict>
                        <key>PayloadDisplayName</key>
                        <string>$ICAcertname</string>
                        <key>PayloadType</key>
                        <string>com.apple.security.pkcs1</string>
                        <key>PayloadUUID</key>
                        <string>$uuid2</string>
                        <key>PayloadIdentifier</key>
                        <string>com.apple.security.pkcs1.$uuid2</string>
                        <key>PayloadVersion</key>
                        <integer>1</integer>
                        <key>PayloadContent</key>
                        <data>
                                $cert
                        </data>
                </dict>
EOS
}

my $xmltext = <<"EOS";
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
        <key>PayloadDisplayName</key>
        <string>$PayloadDisplayName</string>
        <key>PayloadIdentifier</key>
        <string>$PLID</string>
        <key>PayloadRemovalDisallowed</key>
        <false/>
        <key>PayloadType</key>
        <string>Configuration</string>
        <key>PayloadUUID</key>
        <string>$PLuuid</string>
        <key>PayloadVersion</key>
        <integer>1</integer>
${xml_Expire}   <key>PayloadContent</key>
        <array>
                <dict>
                        <key>AutoJoin</key>
                        <true/>
                        <key>CaptiveBypass</key>
                        <false/>
                        <key>DisableAssociationMACRandomization</key>
                        <false/>
                        <key>DisplayedOperatorName</key>
                        <string>$friendlyName</string>
                        <key>DomainName</key>
                        <string>$HomeDomain</string>
                        <key>EAPClientConfiguration</key>
                        <dict>
                                <key>AcceptEAPTypes</key>
                                <array>
                                        <integer>21</integer>
                                </array>
                                <key>TLSTrustedServerNames</key>
                                <array>
                                        <string>$AAAFQDN</string>
                                </array>
${xml_anchor}                           <key>TTLSInnerAuthentication</key>
                                <string>MSCHAPv2</string>
                                <key>UserName</key>
                                <string>$uname</string>
                                <key>UserPassword</key>
                                <string>$passwd</string>
                                <key>OuterIdentity</key>
                                <string>$anonID</string>
                        </dict>
                        <key>EncryptionType</key>
                        <string>WPA2</string>
                        <key>HIDDEN_NETWORK</key>
                        <false/>
                        <key>IsHotspot</key>
                        <true/>
                        <key>PayloadDescription</key>
                        <string>$description</string>
                        <key>PayloadDisplayName</key>
                        <string>Wi-Fi</string>
                        <key>PayloadIdentifier</key>
                        <string>com.apple.wifi.managed.$uuid1</string>
                        <key>PayloadType</key>
                        <string>com.apple.wifi.managed</string>
                        <key>PayloadUUID</key>
                        <string>$uuid1</string>
                        <key>PayloadVersion</key>
                        <integer>1</integer>
                        <key>ProxyType</key>
                        <string>None</string>
${xml_RCOI}${xml_NAI}                   <key>ServiceProviderRoamingEnabled</key>
                        <true/>
                </dict>
$xml_cert       </array>
</dict>
</plist>
EOS

print <<EOS;
Content-Type: application/x-apple-aspen-config

EOS

#if ($signercert eq '') {
    print $xmltext;
#} else {
#    if ($signerchain eq '') {
#        open(fh, "| openssl smime -sign -nodetach -signer $signercert -inkey $signerkey -outform der");
#    } else {
#        open(fh, "| openssl smime -sign -nodetach -certfile /home/computercenter/PPWP/helper/chain.pem -signer $signercert -inkey $signerkey -outform der");
#    }
#    print fh $xmltext;
#    close(fh);
#}

exit(0);

