#!/usr/bin/perl
#
# Passpoint Provisioning Tools
#  Simple CGI script for Passpoint profile provisioning
#  Target: Android 10+
# 
# Usage:
#  - Customize the configuration part below.
#  - Put this script on a web server as a CGI program.
#  - Access https://<path_to_script>/passpoint-android.config by Chrome.
# Notes:
#  - Server authentication works on Android 11+.
#  - Avoid PAP since Android 10 cannot configure server authentication
#    through PPS-MO.
#    (vulnerable to evil-twin AP attacks)
#  - (The current) PPS-MO does not have a field for specifying Outer
#    Identity explicitly. The current Android implementation forms
#    Outer Identity automatically based on the Credential/Realm.
# References:
#  - Passpoint (Hotspot 2.0)
#    https://source.android.com/devices/tech/connect/wifi-passpoint
#
# 20220721 Hideaki Goto (Cityroam/eduroam)
# 20220722 Hideaki Goto (Cityroam/eduroam)
# 20220729 Hideaki Goto (Cityroam/eduroam)
# 20220812 Hideaki Goto (Cityroam/eduroam)	+ expiration date
# 20220826 Hideaki Goto (Cityroam/eduroam)	+ per-user ExpirationDate
# 20230529 Hiroyuki Harada (Sapporo Gakuin University)
#

use CGI;
use DateTime;
use MIME::Base64;


#---- Configuration part ----

# include common settings
require '/path/to/helper/pp-common.cfg';

my ($userID, $passwd) = @ARGV;

$uname = $anonID = $userRealm = $userID;
$anonID =~ s/^.*@/anonymous@/;
$userRealm =~ s/^.*@//;

# override the NAI realm since Android use it for outer identity
$NAIrealm = $userRealm;


#---- Profile composition part ----
# (no need to edit below, hopefully)

$ts=DateTime->now->datetime."Z";
$encpass = encode_base64($passwd);
chomp($encpass);

$xml_Expire = '';
if ( $ExpirationDate ne '' ){
$xml_Expire = <<"EOS";
        <Node>
          <NodeName>ExpirationDate</NodeName>
          <Value>$ExpirationDate</Value>
        </Node>
EOS
}

$RCOI =~ s/\s*//g;
$xml_RCOI = '';
if ( $RCOI ne '' ){
$xml_RCOI = <<"EOS";
        <Node>
          <NodeName>RoamingConsortiumOI</NodeName>
          <Value>$RCOI</Value>
        </Node>
EOS
}

$xmltext = <<"EOS";
<MgmtTree xmlns="syncml:dmddf1.2">
  <VerDTD>1.2</VerDTD>
  <Node>
    <NodeName>PerProviderSubscription</NodeName>
    <RTProperties>
      <Type>
        <DDFName>urn:wfa:mo:hotspot2dot0-perprovidersubscription:1.0</DDFName>
      </Type>
    </RTProperties>
    <Node>
      <NodeName>i001</NodeName>
      <Node>
        <NodeName>HomeSP</NodeName>
        <Node>
          <NodeName>FriendlyName</NodeName>
          <Value>$friendlyName</Value>
        </Node>
        <Node>
          <NodeName>FQDN</NodeName>
          <Value>$HomeDomain</Value>
        </Node>
${xml_RCOI}      </Node>
      <Node>
        <NodeName>Credential</NodeName>
        <Node>
          <NodeName>CreationDate</NodeName>
          <Value>$ts</Value>
        </Node>
${xml_Expire}        <Node>
          <NodeName>Realm</NodeName>
          <Value>$NAIrealm</Value>
        </Node>
        <Node>
          <NodeName>UsernamePassword</NodeName>
          <Node>
            <NodeName>Username</NodeName>
            <Value>$uname</Value>
          </Node>
          <Node>
            <NodeName>Password</NodeName>
            <Value>$encpass</Value>
          </Node>
          <Node>
            <NodeName>MachineManaged</NodeName>
            <Value>true</Value>
          </Node>
          <Node>
            <NodeName>EAPMethod</NodeName>
            <Node>
              <NodeName>EAPType</NodeName>
              <Value>21</Value>
            </Node>
            <Node>
              <NodeName>InnerMethod</NodeName>
              <Value>MS-CHAP-V2</Value>
            </Node>
          </Node>
        </Node>
      </Node>
      <Node>
        <NodeName>Extension</NodeName>
        <Node>
          <NodeName>Android</NodeName>
          <Node>
            <NodeName>AAAServerTrustedNames</NodeName>
            <Node>
              <NodeName>FQDN</NodeName>
              <Value>$AAAFQDN</Value>
            </Node>
          </Node>
        </Node>
      </Node>
    </Node>
  </Node>
</MgmtTree>
EOS

$xmlb64 = encode_base64($xmltext);
chomp($xmlb64);

$cert = '';
$inside_section = 0;

open my $fh, '<', $CAfile;
while(<$fh>){
    if ( $_ =~ /BEGIN\s+CERTIFICATE/ ){
        $inside_section = 1;
        next;
    }
    if ( $_ =~ /END\s+CERTIFICATE/ ){
        if ($inside_section) {
            $inside_section = 0;
            next;
        }
    }
    if ($inside_section){
        $cert .= $_;
    }
}
close $fh;
$cert =~ s/\r//g;
chomp($cert);

$mm = <<"EOS";
Content-Type: multipart/mixed; boundary={boundary}
Content-Transfer-Encoding: base64

--{boundary}
Content-Type: application/x-passpoint-profile
Content-Transfer-Encoding: base64

$xmlb64
--{boundary}
Content-Type: application/x-x509-ca-cert
Content-Transfer-Encoding: base64

$cert
--{boundary}--
EOS


# Output of the composed profile

print encode_base64($mm);
#print $mm;

exit(0);
