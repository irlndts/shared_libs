package oauthc;

use strict;
use DBI;
use Cache::Memcached;
use POSIX;
use utf8;
use Encode;
use LWP;

use OAuth::Lite::Util qw(gen_random_key encode_param decode_param create_signature_base_string parse_auth_header);
use OAuth::Lite::ServerUtil;
use OAuth::Lite::SignatureMethod::HMAC_SHA1;

use oauths;
use js;
use mc;
use uri;


# Проверка авторизации для конкретного ресурса
# Параметры:
#	$oauth_url - URL проверки авторизации OAuth сервера
#	$header - HTTP заголосовок Authorization (содержимое)
#	$r_method - метод оригинального запроса, для которого проверяется авторизация
#	$r_url - url оригинального запроса, для которого проверяется авторизация
#	$msisdn - msisdn для которого проверяется действие
#	$memc - соединение к мемкэшу OAuth сервера
#	$params - в случае, если переданы параметры, взять их, а не те, что были получены только из заголовков
# Возвращает массив из двух элементов:
#	res - хэшь с доступом к ресурсам (из токена)
#		undef - не прошла авторизация
#	msisdn - msisdn пользователя из токена доступа
#		Для того, что-бы получить msisdn, обязательно необходимо
#		что-бы параметр $memc указывал на соединение с мемкэшем OAuth.
#		Иначе в качестве msisdn будет возвращаться undef
#	details - детали при неудачной авторизации
sub check_oauth {
	my ($oauth_url, $header, $r_method, $r_url, $msisdn, $memc, $params) = @_;

	my $res;
	my $tmsisdn; # msisdn из токена для возврата
	my $details = '';
	
	my $original_params = $params||undef;

	if (!defined $oauth_url) {
		$details = '0: Bad method params';
		return ($res, $tmsisdn, $details);
	}

	# Получаем все параметры из заголовка Authorization
	my ($realm, $paramsTMP) = parse_auth_header($header);
	# Если параметры не определены, задать их только из заголовка
	if (!defined $params) {
		$params = $paramsTMP;
	} else {
		#Добавляем параметры в запрос на OAUTh					
		$oauth_url = $oauth_url."?";				
		for my $key (keys %{$params}) {
			$oauth_url = $oauth_url."$key=".${$params}{$key}."&";				
		}
		substr($oauth_url,-1) = "";
		###################################3

		# Объедить переданные парамтеры с парамтерами в запросе
		foreach my $env (keys %{$paramsTMP}) {
			# Заменить элемент на массив
			if ((defined $params->{$env})&&(!ref $params->{$env})) {
				my $array = ();
				push @{$array}, $params->{$env};
				push @{$array}, $paramsTMP->{$env};
				$params->{$env} = ();
				$params->{$env} = $array;
			} elsif ((defined $params->{$env})&&(ref $params->{$env} eq 'ARRAY')) {
				# Если массив, то просто дописать в нег онудное значение
				push @{$params->{$env}}, $paramsTMP->{$env};
			} elsif (defined $paramsTMP->{$env}){
				$params->{$env} = $paramsTMP->{$env};
			} else {
				$params->{$env} = '';
			}
		}
	}
#	open("F",">/tmp/cqspel.txt");
#	foreach my $key (keys %{$params}) {
#		if ((defined $params->{$key})&&(!ref $params->{$key})) {
#			print F "$key = ".$params->{$key}."\n";
#		} elsif ((defined $params->{$key})&&(ref $params->{$key} eq 'ARRAY')) {
#			print F "Array found \n";
#			for (my $i=0;$i<@{$params->{$key}};$i++){
#				print F "\t".$params->{$key}->[$i]."\n";
#			}
#		} elsif (defined $params->{$key}) {
#			print F ref($params->{$key})."\n";
#		}
#	}
#	close(F);

	# 1. Проверка ЭЦП запроса
	my $sutil = OAuth::Lite::ServerUtil->new(strict => 0);
	$sutil->support_signature_methods(qw/HMAC_SHA1/);

	if ($sutil->validate_params($params)) {
		if ($sutil->validate_signature_method($params->{oauth_signature_method})) {
			if (defined($params->{oauth_token}) && ($params->{oauth_token} ne '')) {
				my $token = get_token_access_memc($memc, $params->{oauth_token});
				my $client = get_client_memc($memc, $token->{client}) if (defined($token));

				if (defined($token) && defined($client)) { $oauth_url =~ s/\?.+//g;

					# Если передан msisdn - сверяем с токеном
					if (!defined($msisdn) || ($msisdn eq '') || ($msisdn eq $token->{msisdn})) {
						$tmsisdn = $token->{msisdn};
							
						if ($sutil->verify_signature(method => $r_method, params => $params, url => $r_url, token_secret => $token->{secret}, consumer_secret => $client->{client_secret})) {
							# По данным токена проверяем разрешение для ресурсов
							foreach my $tr (@{$token->{resources}}) {
								$res->{$tr} = 1;
							};
						} else {
							$details .= '1: Bad header signature | ';
						};
					} else {
						$details .= '2: Different msisdns in params & token | ';
					};
				} else {
					# Делаем HTTP запрос на https://oauth.vasmedia.ru/status для проверки доступа
					# Оригинальный URL и метод передаем через заголовки X-Original-URL и X-Original-Method

					my $browser = LWP::UserAgent->new();
					$browser->timeout(10);
			


					my $response = $browser->post($oauth_url,
						content_type => 'application/json' ,
						Content => '{"msisdn":"'.$msisdn.'"}',
						'Authorization' => $header,
						'X-Original-URL' => $r_url,
						'X-Original-Method' => $r_method,
					);

					if ($response->is_success) {
						my $json = $response->content();
						if (defined($json) && ($json ne '')) {
							my $j = js::to_hash($json);

							if (defined($j) && defined($j->{result})) {
								if ($j->{result} eq '200') {
									# Если определен $memc - извлекаем токен из мемкэша и берем из него msisdn
									$res = $j->{resources};
									$tmsisdn = $j->{msisdn};
=test
									if (defined($memc)) {
										$token = get_token_access_memc($memc, $params->{oauth_token});
										$tmsisdn = $token->{msisdn} if (defined($token));
										$res = $token->{resources} if (defined($token));
									} else {
										# Если не определ memcache - берем доступные данные из ответа OAuth сервера
										$res = $j->{resources};
										$tmsisdn = $j->{msisdn};
									};
=cut
								} else {
									$details .= '6: No 200 result in OAuth server response | ';
								};
							} else {
								$details .= '5: No JSON in OAuth server response | ';
							};
						} else {
							$details .= '4: No content in OAuth server response | ';
						};
					} else {
						$details .= '3: Bad request to AOuth server | ';
					};
				};
			};
		};
	};

	return($res, $tmsisdn, $details);
};

sub get_token_access_memc {
	my ($memc, $tokenstr) = @_;

	my $t = mc::get($memc, 'token_access', $tokenstr);

	return($t);
};

sub get_client_memc {
	my ($memc, $clientstr) = @_;

	my $clt = mc::get($memc, 'client', $clientstr);

	return($clt);
};


1;
