#!/usr/bin/perl
#
# Passpointプロビジョニングツール
#  PasspointプロファイルのプロビジョニングのためのシンプルなCGIスクリプト
#  対象: Windows 11 22H2+
#
# 使用方法:
#  - ms-settings:wifi-provisioning?uri=スキームを使用してスクリプトにアクセスします。
#    <a href="ms-settings:wifi-provisioning?uri=https://<path_to_script>/passpoint-win.config"> ... </a>
# 参考資料:
#  https://docs.microsoft.com/en-us/windows-hardware/drivers/mobilebroadband/account-provisioning
#  https://docs.microsoft.com/en-us/windows-hardware/drivers/mobilebroadband/update-the-hotspot-authentication-sample
#  https://docs.microsoft.com/en-us/windows/win32/nativewifi/wlan-profileschema-elements
#  https://docs.microsoft.com/en-us/windows/uwp/launch-resume/launch-settings-app
#
# 20220729 Hideaki Goto (Cityroam/eduroam)
# 20230118 Hideaki Goto (Cityroam/eduroam)	+ Script URI auto-setting
# 20230510 Hideaki Goto (Cityroam/eduroam)	+ Fixed very rare key conflict in redis#
# 20230523 Hiroyuki Harada (Sapporo Gakuin University)	For PasspointProvisioningWebApp
#

use CGI;
use CGI qw(param);
use Digest::SHA qw(sha1);
use MIME::Base64 qw(encode_base64);
use XML::Compile::C14N;
use XML::Compile::C14N::Util qw(:c14n);
use XML::LibXML;
use Crypt::OpenSSL::RSA;
use File::Slurp qw(read_file);

if (scalar(@ARGV) != 2) {
    die "引数の数が正しくありません。\n";
}

# 引数を変数に格納する
my ($userID, $passwd) = @ARGV;

my $q = CGI->new();

#---- Configuration part ----

my $anonID = $userID;
$anonID =~ s/^.*@/anonymous@/;	# outer identity

# include common settings
require '/path/to/helper/pp-common.cfg';


#---- Profile composition part ----
# (no need to edit below, hopefully)

my $xml_SSID = $SSID ? <<"EOS" : '';
      <SSIDConfig>
        <SSID>
          <name>$SSID</name>
        </SSID>
      </SSIDConfig>
EOS

my $xml_RCOI = '';
if ($RCOI) {
    $RCOI = lc $RCOI;
    my $xml_OIs = join "\n", map { "          <OUI>$_</OUI>" } split(/,/, $RCOI);
    $xml_RCOI = "        <RoamingConsortium>\n$xml_OIs\n        </RoamingConsortium>\n";
}

my $xml = <<"EOS";
<CarrierProvisioning xmlns="http://www.microsoft.com/networking/CarrierControl/v1" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><Global><CarrierId>{$CarrierId}</CarrierId><SubscriberId>$SubscriberId</SubscriberId></Global><WLANProfiles><WLANProfile xmlns="http://www.microsoft.com/networking/CarrierControl/WLAN/v1"><name>$friendlyName</name>${xml_SSID}<Hotspot2><DomainName>$HomeDomain</DomainName><NAIRealm><name>$NAIrealm</name></NAIRealm>${xml_RCOI}</Hotspot2><MSM><security><authEncryption><authentication>WPA2</authentication><encryption>AES</encryption><useOneX>true</useOneX></authEncryption><OneX xmlns="http://www.microsoft.com/networking/OneX/v1"><authMode>user</authMode><EAPConfig><EapHostConfig xmlns="http://www.microsoft.com/provisioning/EapHostConfig"><EapMethod><Type xmlns="http://www.microsoft.com/provisioning/EapCommon">21</Type><VendorId xmlns="http://www.microsoft.com/provisioning/EapCommon">0</VendorId><VendorType xmlns="http://www.microsoft.com/provisioning/EapCommon">0</VendorType><AuthorId xmlns="http://www.microsoft.com/provisioning/EapCommon">311</AuthorId></EapMethod><Config><EapTtls xmlns="http://www.microsoft.com/provisioning/EapTtlsConnectionPropertiesV1"><ServerValidation><ServerNames>$AAAFQDN</ServerNames><TrustedRootCAHash>$TrustedRootCAHash</TrustedRootCAHash><DisablePrompt>false</DisablePrompt></ServerValidation><Phase2Authentication><MSCHAPAuthentication/></Phase2Authentication><Phase1Identity><IdentityPrivacy>true</IdentityPrivacy><AnonymousIdentity>$anonID</AnonymousIdentity></Phase1Identity></EapTtls></Config></EapHostConfig></EAPConfig></OneX><EapHostUserCredentials xmlns="http://www.microsoft.com/provisioning/EapHostUserCredentials" xmlns:baseEap="http://www.microsoft.com/provisioning/BaseEapMethodUserCredentials" xmlns:eapCommon="http://www.microsoft.com/provisioning/EapCommon"><EapMethod><eapCommon:Type>21</eapCommon:Type><eapCommon:AuthorId>311</eapCommon:AuthorId></EapMethod><Credentials><EapTtls xmlns="http://www.microsoft.com/provisioning/EapTtlsUserPropertiesV1"><Username>$userID</Username><Password>$passwd</Password></EapTtls></Credentials></EapHostUserCredentials></security></MSM></WLANProfile>
  </WLANProfiles>
</CarrierProvisioning>
EOS


# Perl version of signing below.

my $c14n   = XML::Compile::C14N->new(type => '1.0');

chomp $xml;
my $xml1 = $xml;
$xml1 =~ s/<\/CarrierProvisioning>//;
my $xml2 = '</CarrierProvisioning>';

$parser = XML::LibXML->new();
$dom = $parser->parse_string($xml);

my $cano = $c14n->normalize(C14N_v10_NO_COMM, $dom);

$digest = sha1($cano);
$dgstb64 = encode_base64($digest);
chomp $dgstb64;

my $si = <<"EOS";
<CanonicalizationMethod Algorithm="http://www.w3.org/TR/2001/REC-xml-c14n-20010315" /><SignatureMethod Algorithm="http://www.w3.org/2000/09/xmldsig#rsa-sha1" /><Reference URI=""><Transforms><Transform Algorithm="http://www.w3.org/2000/09/xmldsig#enveloped-signature" /></Transforms><DigestMethod Algorithm="http://www.w3.org/2000/09/xmldsig#sha1" /><DigestValue>$dgstb64</DigestValue></Reference></SignedInfo>
EOS

$si =~ s/\s*//;
$si =~ s/\s*$//;
$si =~ s/\s*\d?\n\s*//g;
# also chomp-ed

$si_out = '<SignedInfo xmlns="http://www.w3.org/2000/09/xmldsig#">'.$si;
$si = '<SignedInfo xmlns="http://www.w3.org/2000/09/xmldsig#" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'.$si;

$dom = $parser->parse_string($si);
$si_cano = $c14n->normalize(C14N_v10_NO_COMM, $dom);

my $privkey = read_file($signerkey);
my $rsa_privkey = Crypt::OpenSSL::RSA->new_private_key($privkey);
my $sign = $rsa_privkey->sign($si_cano);

$sigval = encode_base64($sign, "");
chomp $sigval;


# read signer cert.

my $cert1 = '';

sub read_file {
    my ($file) = @_;
    open(my $fh, '<', $file) or return '';
    local $/ = undef;
    my $content = <$fh>;
    close($fh);
    return $content;
}

$cert1 .= read_file($signercert) if $signercert ne '';
$cert1 .= read_file($CAfile_win) if $CAfile_win ne '';

$cert1 =~ s/-----BEGIN\s+CERTIFICATE-----\n/<X509Certificate>/g;
$cert1 =~ s/\n-----END\s+CERTIFICATE-----\n/<\/X509Certificate>/g;
chomp $cert1;

# form Signature block

$signature = <<"EOS";
<Signature xmlns="http://www.w3.org/2000/09/xmldsig#">$si_out<SignatureValue>$sigval</SignatureValue><KeyInfo><X509Data>$cert1</X509Data></KeyInfo></Signature>
EOS
chomp $signature;

print "<?xml version=\"1.0\"?>\n";
print "$xml1$signature$xml2\n";

exit(0);
