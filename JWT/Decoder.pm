package JWT::Decoder;

use strict;
use lib '/home/projects/SHARED_API';
use Crypt::RSA;
use Crypt::RSA::Key::Private;
use MIME::Base64 qw( encode_base64 decode_base64);
use Crypt::GCM;
use Crypt::Rijndael;
use JWT::Client;
use Digest::MD5 qw(md5_hex);
use js;
use Data::Dumper;

# декодирование полученного токена
# INPUT PARAMS:
#$tokenSimple строка с токеном
#$clientId - id партнера
sub decode {
	my ($log, $dbh, $memc, $tokenSimple, $clientId) = @_;
# проверим полученные параметроры на валидность
	$log->sysLog('alert', 'in decode');
	my $badCheckResult = checkInputParams($tokenSimple, $clientId);
# вернем ошибочный статус, если какой-то из параметров не валилен
	return $badCheckResult if $badCheckResult;
# разделим на части полученный токен, используя разделитель "."
	my $client_secret_key = get_secret_key($log, $dbh, $memc, $clientId);
	return { result => 403, details => "no secret ky for client: ".$clientId } unless $client_secret_key;
	$log->sysLog('alert', "got secret key: ".$client_secret_key);
	my ($Encoded_JWE_Header,
	 	$Encoded_JWE_Encrypted_Key,
	 	$Encoded_JWE_Initialization_Vector,
	 	$Encoded_JWE_Ciphertext,
	 	$Encoded_JWE_Authentication_Tag) = split(/\./, $tokenSimple);

	my $JWE_Header = decode_base64($Encoded_JWE_Header);

	my $Decoded_JWE_Initialization_Vector = decode_base64($Encoded_JWE_Initialization_Vector);

	my $Decoded_JWE_Authentication_Tag = decode_base64($Encoded_JWE_Authentication_Tag);

	my $Decoded_JWE_Ciphertext = decode_base64($Encoded_JWE_Ciphertext);

	my $Decoded_JWE_Encrypted_Key = decode_base64($Encoded_JWE_Encrypted_Key);
# создадим объект расшифровки с использованием шифрования 'OAEP'
	my $rsa_client = new Crypt::RSA ( ES => 'OAEP' );
# загрузим из файла секретный ключ, принадлежащий партнеру с полученным id
	my $client_private_key_obj = Crypt::RSA::Key::Private->new()->deserialize(String	=>	[$client_secret_key]);
	# читаем клиентский секретный ключ из файла
	my $Decoded_Content_Encryption_Key = $rsa_client->decrypt (	Cyphertext	=> $Decoded_JWE_Encrypted_Key,
																Key		=> $client_private_key_obj,
																#Armour	=> 1
																) || die $rsa_client->errstr();
	#############################################
	####
	####	Дешифруем Claim set
	####
	#############################################

	my $decipher = Crypt::GCM->new(	-key => $Decoded_Content_Encryption_Key,
									-cipher => 'Crypt::Rijndael');
	$decipher->set_iv($Decoded_JWE_Initialization_Vector);
	$decipher->aad('');
	$decipher->tag($Decoded_JWE_Authentication_Tag);
	my $decoded_claimsString = $decipher->decrypt($Decoded_JWE_Ciphertext);
	my $decoded_claims = js::to_hash($decoded_claimsString);
# вернем расшифрованные клэймы
	return $decoded_claims;
};


# проверка входных параметров на корректность
sub checkInputParams {
	my ($tokenSimple, $clientId) = @_;
# не передан токен
	return {result => 403, details => 'empty token'} unless $tokenSimple;
# непередан id партнера
	return {result => 403, details => 'empty clientId'} unless $clientId;
# вернем хороший статус - ничего плохого не нашли
	return undef;
};


sub get_secret_key {
	my ($log, $dbh, $memc, $clientId) = @_;
	$log->sysLog('alert', 'will get secret key for: '.$clientId);
	my $client_secret_key = get_memc_key($memc, $clientId."::secret");
		
	return $client_secret_key;
};


sub get_memc_key {
	my ($memc, $key) = @_;
	return mc::get($memc, 'jwt', $key) || undef;
};



1;