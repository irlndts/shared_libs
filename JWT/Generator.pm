package JWT::Generator;

use strict;
use lib '/home/projects/SHARED_API';
use js;
use libs;
use MIME::Base64 qw( encode_base64 decode_base64);
use Crypt::RSA;
use Crypt::GCM;
use Crypt::Rijndael;
use JWT::Client;
use Data::Dumper;


#TODO: упразнить массивы, а хранить в строки. мб лучше генерить.
##### INIT PARAMS #########
	my @Content_Encryption_Key_Array = (177, 161, 244, 128, 84, 143, 225, 115, 63, 180, 3, 255, 107, 154, 212, 246, 138, 7, 110, 91, 112, 46, 34, 105, 47, 130, 203, 46, 122, 234, 64, 252);
	my @modulus_array = (161, 168, 84, 34, 133, 176, 208, 173, 46, 176, 163, 110, 57, 30, 135, 227, 9, 31, 226, 128, 84, 92, 116, 241, 70, 248, 27, 227, 193, 62, 5, 91, 241, 145, 224, 205, 141, 176, 184, 133, 239, 43, 81, 103, 9, 161, 153, 157, 179, 104, 123, 51, 189, 34, 152, 69, 97, 69, 78, 93, 140, 131, 87, 182, 169, 101, 92, 142, 3, 22, 167, 8, 212, 56, 35, 79, 210, 222, 192, 208, 252, 49, 109, 138, 173, 253, 210, 166, 201, 63, 102, 74, 5, 158, 41, 90, 144, 108, 160, 79, 10, 89, 222, 231, 172, 31, 227, 197, 0, 19, 72, 81, 138, 78, 136, 221, 121, 118, 196, 17, 146, 10, 244, 188, 72, 113, 55, 221, 162, 217, 171, 27, 57, 233, 210, 101, 236, 154, 199, 56, 138, 239, 101, 48, 198, 186, 202, 160, 76, 111, 234, 71, 57, 183, 5, 211, 171, 136, 126, 64, 40, 75, 58, 89, 244, 254, 107, 84, 103, 7, 236, 69, 163, 18, 180, 251, 58, 153, 46, 151, 174, 12, 103, 197, 181, 161, 162, 55, 250, 235, 123, 110, 17, 11, 158, 24, 47, 133, 8, 199, 235, 107, 126, 130, 246, 73, 195, 20, 108, 202, 176, 214, 187, 45, 146, 182, 118, 54, 32, 200, 61, 201, 71, 243, 1, 255, 131, 84, 37, 111, 211, 168, 228, 45, 192, 118, 27, 197, 235, 232, 36, 10, 230, 248, 190, 82, 182, 140, 35, 204, 108, 190, 253, 186, 186, 27);
	my @public_exponent_array = (1, 0, 1);
	my @private_exponent_array = (144, 183, 109, 34, 62, 134, 108, 57, 44, 252, 10, 66, 73, 54, 16, 181, 233, 92, 54, 219, 101, 42, 35, 178, 63, 51, 43, 92, 119, 136, 251, 41, 53, 23, 191, 164, 164, 60, 88, 227, 229, 152, 228, 213, 149, 228, 169, 237, 104, 71, 151, 75, 88, 252, 216, 77, 251, 231, 28, 97, 88, 193, 215, 202, 248, 216, 121, 195, 211, 245, 250, 112, 71, 243, 61, 129, 95, 39, 244, 122, 225, 217, 169, 211, 165, 48, 253, 220, 59, 122, 219, 42, 86, 223, 32, 236, 39, 48, 103, 78, 122, 216, 187, 88, 176, 89, 24, 1, 42, 177, 24, 99, 142, 170, 1, 146, 43, 3, 108, 64, 194, 121, 182, 95, 187, 134, 71, 88, 96, 134, 74, 131, 167, 69, 106, 143, 121, 27, 72, 44, 245, 95, 39, 194, 179, 175, 203, 122, 16, 112, 183, 17, 200, 202, 31, 17, 138, 156, 184, 210, 157, 184, 154, 131, 128, 110, 12, 85, 195, 122, 241, 79, 251, 229, 183, 117, 21, 123, 133, 142, 220, 153, 9, 59, 57, 105, 81, 255, 138, 77, 82, 54, 62, 216, 38, 249, 208, 17, 197, 49, 45, 19, 232, 157, 251, 131, 137, 175, 72, 126, 43, 229, 69, 179, 117, 82, 157, 213, 83, 35, 57, 210, 197, 252, 171, 143, 194, 11, 47, 163, 6, 253, 75, 252, 96, 11, 187, 84, 130, 210, 7, 121, 78, 91, 79, 57, 251, 138, 132, 220, 60, 224, 173, 56, 224, 201);
	my @JWE_Initialization_Vector_Array = (227, 197, 117, 252, 2, 219, 233, 68, 180, 225, 77, 219);
	my @Additional_Authenticated_Data_Array = (101, 121, 74, 104, 98, 71, 99, 105, 79, 105, 74, 83, 85, 48, 69, 116, 84, 48, 70, 70, 85, 67, 73, 115, 73, 109, 86, 117, 89, 121, 73, 54, 73, 107, 69, 121, 78, 84, 90, 72, 81, 48, 48, 105, 102, 81);
	
	#my ($client_public_key, $client_private_key) = (undef, undef);
	#my ($server_public_key, $server_private_key) = (undef, undef);
##### END OF INIT PARAMS ######

##### NORMALIZED PARAMS #####
	my ($modulus, $public_exponent, $private_exponent) = ('', '', '');
	my $client_public_key = undef;
	my $JWE_Initialization_Vector = '';
	my $Additional_Authenticated_Data = '';
	my $Content_Encryption_Key = '';
#### END OF NORMALIZED PARAMS #####
sub _normalizeParam {
	my (@array) = @_;
	my $array_size = $#array+1;
	my $result = '';
	for (my $i = 0; $i < $array_size; $i++) {
		$result .= chr($array[$i]);
	};
	return $result;
}
sub _normalizeParams {
	$JWE_Initialization_Vector = _normalizeParam(@JWE_Initialization_Vector_Array);
	$Additional_Authenticated_Data = _normalizeParam(@Additional_Authenticated_Data_Array);
	$modulus = _normalizeParam(@modulus_array);
	$public_exponent = _normalizeParam(@public_exponent_array);
	$private_exponent = _normalizeParam(@private_exponent_array);
	$Content_Encryption_Key = _normalizeParam(@Content_Encryption_Key_Array);

	# Оригинальный текст
	my $orig_text = "The true sign of intelligence is not knowledge but imagination.";	
	
}

# здесь происходит формирование JWT
# Input params:
#  $resources  - hashref  с ресурсами, которые будут доступны по ключу
#  $msisdn - msisdn...
# $clientId- это consumer_id, переданный в http запросе к нам. по этому параметру будет полдгружаться секретный ключ
# Output param:
# $result_token - в случае успешного формирования токена
#      ИЛИ 
# $BadCheckResult - в случае, если были переданы кривые входные параметры
sub generate {
	my ($dbh, $memc, $resources, $msisdn, $clientId) = @_;
	my $expire = time() + 60;
# проверим переданные параметры на их корректность
	my $BadCheckResult = checkInputParams($msisdn, $clientId);
	return $BadCheckResult if $BadCheckResult;
	_normalizeParams();
# кодируем заголовок
	my $JWE_Header = '{"alg":"RSA-OAEP","enc":"A256GCM"}';
	my $Encoded_JWE_Header = encode_base64($JWE_Header);
	$Encoded_JWE_Header =~ s/[\r\n]+//g;
# сформируем claims, в которых будет содержаться информация о сроке валидности токена, msisdn и доступных для токена ресурсов
	my $claim = _getClaimJSON($msisdn, $expire, $resources);

# дальше формируются части токена, которые далее будут сконкатенированы
	my $Encoded_JWE_Encrypted_Key = _encode_Encrypted_Key($dbh, $memc, $clientId);
	my $Encoded_JWE_Initialization_Vector = _encode_Initialization_Vector();
	my ($cipher, $Encoded_JWE_Ciphertext) = _encode_Ciphertext($claim, $Content_Encryption_Key, $JWE_Initialization_Vector);
	my $Encoded_JWE_Authentication_Tag = _encode_Authentication_Tag($cipher);
	
	my $result_token = $Encoded_JWE_Header.".".$Encoded_JWE_Encrypted_Key.".".$Encoded_JWE_Initialization_Vector.".".$Encoded_JWE_Ciphertext.".".$Encoded_JWE_Authentication_Tag;
	return $result_token;	
};

# проверка входных параметров на корректность
sub checkInputParams {
	my ($msisdn, $clientId) = @_;

	return {result => 403, details => 'bad format or empty msisdn'} unless libs::is_good_msisdn($msisdn);
	return {result => 403, details => 'no clientId was passed as input argument'} unless $clientId;
# вернем хороший статус - ничего плохого не нашли
	return undef;
};

# формирование claims  в формате JSON
sub _getClaimJSON {
	my ($msisdn, $expire, $resources) = @_;
	my $claim = {	exp => $expire,
					aud => "Empty",
					iss => "Empty",
					prn => $msisdn,
					res => $resources,
				};
	return js::from_hash($claim);
};


######## в этих сабах идет формирование частей токена ######################

sub _encode_Encrypted_Key {
	my ($dbh, $memc, $clientId) = @_;
	_normalizeParams();
	my $client_public_key = get_memc_key($memc, $clientId."::public");
	
	unless ($client_public_key) {
		$client_public_key = get_jwt_public_key_from_db($dbh, $clientId);
		set_memc_key($memc, $clientId."::public", $client_public_key) if $client_public_key;
	};

	my $client_secret_key = get_memc_key($memc, $clientId."::secret");
	
	unless ($client_secret_key) {
		$client_secret_key = get_jwt_secret_key_from_db($dbh, $clientId);
		set_memc_key($memc, $clientId."::secret", $client_secret_key) if $client_secret_key;
	};
	return undef unless $client_public_key;
	
	# Грузим ключи для шифрования
	my $rsa_server = new Crypt::RSA ( ES => 'OAEP' );	
	# читаем клиентский секретный ключ из файла
	# my $client_public_key_obj = new Crypt::RSA::Key::Public();
	
	my $client_public_key_obj = Crypt::RSA::Key::Public->new()->deserialize(String	=>	[$client_public_key]);
	
	# Шифруем по алгоритму RSAES OAEP, используя клиентский публичный ключ
	my $JWE_Encrypted_Key = $rsa_server->encrypt (	Message	=> $Content_Encryption_Key,
													Key		=> $client_public_key_obj,
													#Armour	=> 1
												) || die $rsa_server->errstr();
										
	# кодируем Base64
	my $Encoded_JWE_Encrypted_Key = encode_base64($JWE_Encrypted_Key);
	$Encoded_JWE_Encrypted_Key =~ s/[\r\n]+//g;
	return $Encoded_JWE_Encrypted_Key;
};


sub _encode_Initialization_Vector {
	my $Encoded_JWE_Initialization_Vector = encode_base64($JWE_Initialization_Vector);
	$Encoded_JWE_Initialization_Vector =~ s/[\r\n]+//g;
	return $Encoded_JWE_Initialization_Vector;
};


sub _encode_Ciphertext {
	my ($claim, $Content_Encryption_Key, $JWE_Initialization_Vector) = @_;

	my $cipher = Crypt::GCM->new(	-key => $Content_Encryption_Key,
									-cipher => 'Crypt::Rijndael'
								);
	$cipher->set_iv($JWE_Initialization_Vector);
	#$cipher->aad($Additional_Authenticated_Data);
	$cipher->aad('');
	my $JWE_Ciphertext = $cipher->encrypt($claim);
	my $Encoded_JWE_Ciphertext = encode_base64($JWE_Ciphertext);
	$Encoded_JWE_Ciphertext =~ s/[\r\n]+//g;
	return ($cipher, $Encoded_JWE_Ciphertext);
};

sub _encode_Authentication_Tag {
	my ($cipher) = @_;
	my $Authentication_Tag = $cipher->tag;
	my $Encoded_JWE_Authentication_Tag = encode_base64($Authentication_Tag);
	$Encoded_JWE_Authentication_Tag =~ s/[\r\n]+//g;
	return $Encoded_JWE_Authentication_Tag;
};

################ конец саб, в которых формируются части токена ##########

sub get_memc_key {
	my ($memc, $key) = @_;
	return mc::get($memc, 'jwt', $key) || undef;
};

sub set_memc_key {
	my ($memc, $key, $value) = @_;
	return mc::set($memc, 'jwt', $key, $value) || undef;
};

sub get_jwt_public_key_from_db {
	my ($dbh, $clientId) = @_;

	my $req = qq{
		SELECT jwt_public
			FROM clients
		WHERE id = ?;
	};
	my $jwt_public_key = $dbh->selectrow_array($req, undef, $clientId);
	return $jwt_public_key;
};


sub get_jwt_secret_key_from_db {
	my ($dbh, $clientId) = @_;

	my $req = qq{
		SELECT jwt_secret
			FROM clients
		WHERE id = ?;
	};
	my $jwt_public_key = $dbh->selectrow_array($req, undef, $clientId);
	return $jwt_public_key;
};


1;

