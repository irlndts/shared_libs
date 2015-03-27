#!/usr/bin/perl -w
package BAP;

# @tutorial Class Функции работы с BAP платформой
# @version 1.1.0
# @author CQSpel 2012
# @use
#	Logs;
# @since
#        1.1.0
#             Реализация фунцкии регистрации нового абонента в системе

use utf8;
use Encode;
use strict;
use locale;
use LWP::UserAgent;
use Sys::Syslog qw (:standard :macros); 
use XML::DOM;
use Text::Iconv;
use MIME::Parser;
use Switch;
use JSON;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
@ISA       = qw(Exporter);
@EXPORT    = qw(auth_resp);
@EXPORT_OK = qw( );

our $VERSION = '1.1.0';

my $URL		= "https://ttv.staging.loadtomobile.com:443/external/tripletv/";
#my $URLTEST = "https://ttv-test.staging.loadtomobile.com/external/tripletv/";
my $URLTEST = "https://10.236.24.140/external/tripletv/";
my $LOCAL_ADDRESS = '10.236.26.33';

# Глобальный идентификатор объекта
my $BAP = undef;;

sub new {
	my $class=shift;
	my %params = @_;

	# Работы
	my $self = {};
	# Объект входных параметров
	if (defined $params{timeout}) {
		$self->{timeout} = $params{timeout};
	} else {
		$self->{timeout} = 60;
	}
	# Режим дебага
	if (defined $params{debug}) {
		$self->{url}	= $URLTEST;
		$self->{mode}	= 'test';
	} else {
		$self->{url} = $URL;
		$self->{mode}	= 'active';
	}
	$self->{error} = {};
	return $BAP ||= bless($self, $class);
}


# @tutorial Добавляет виртуального пользователя в базу данных БАП
# @params Bigint $msisdn
#	<p>
#		Номер телефона абонента
#	<p>
# @params String $passwd
# @return
#	<p>
#		undef - ошибка выполнения
#		1 - операция выполнена успешно 
#	</p>
sub addNewUserVirtual {
	my $self = shift;
	my $msisdn = shift;
	my $passwd = shift;
	my $group  = shift;
	$self->{error}->{text} = 'OK';

	if ((!defined $msisdn)||(!defined $passwd)) {
		$self->{error}->{text} 		= "Не задан один из обязательных параметров msisdn или puk";
		#$self->{error}->{status} 	= 404;
		$self->{error}->{status} 	= "WRONG FORMAT";
		return undef;
	}

	my $json = JSON->new->utf8;
	# Хеш для команды джейсона

	my $command = {};
	if ($self->{mode} eq 'test') {
		#$command->{command} 		= "password";
		$command->{command} 		= "create";
		$command->{request} 		= "virtual";
		$command->{parameters} 		= {};
		$command->{parameters}->{msisdn} 	= "$msisdn";
		$command->{parameters}->{password} 	= $passwd;
		$command->{parameters}->{group}		= $group;
		$command->{parameters}->{disable_social} = JSON::false,
		$command->{parameters}->{packaging_policy} = "strict";
	} else {
		$command->{command} 		= "password";
		$command->{request} 		= "virtual";
		$command->{parameters} 		= {};
		$command->{parameters}->{msisdn} 	= "$msisdn";
		$command->{parameters}->{password} 	= $passwd;
	}
	my $JSON = to_json($command,{pretty => 1});

	my $ua = LWP::UserAgent->new;
	$ua->timeout($self->{timeout});
	$ua->agent('HEX/1.1.0');
	$ua->local_address($LOCAL_ADDRESS);
	$ua->default_header('Accept-Language' => 'ru, en','Accept-Charset'  => 'utf-8;q=1, *;q=0.1');
	my $response = $ua->post($self->{url},
		Content_Type => 'application/json;charset=utf-8',
		Content => $JSON
	);

	$ua = undef;

	if (!$response->is_success) {
		# Http 404/403/500
		$self->{error}->{text} 		= "Запрос в платформу не выполнен ".$response->status_line();
		$self->{error}->{status} 	= $response->{_rc};
		return undef;
	} else {
		# Запрос выполнен успешно. Распарсить ответ в формате json
		# header 200
		# OK – команда выполнена удачно и происходит формирование и/или отсылка пароля при помощи текстового сообщения со следующем текстом.
		# WrongFormatError		– ошибка составления запроса.
		# WrongGroupError		– не указан идентификатор группы или указан неверный идентификатор группы.
		# WrongIPError 			– запрос прислан не с того IP-адреса.
		# WrongMsisdnError		– неправильный номер абонента или номер не принадлежит сети «Мегафон».
		# WrongPasswordError	– пароль не соответствует установленным правилам.
		# MWProblem-400 – При создании записи MW ответил ошибкой 400.
		# MWProblem-403 – При создании записи MW ответил ошибкой 403.
		# MWProblem-404 		– При создании записи MW ответил ошибкой 404.
		# MWProblem-500 		– При создании записи MW ответил ошибкой 500.
		# TooManyNewPasswordRequests – Сервер авторизации счел, что слишком много запросов на высылку нового пароля для MSISDN;
		# InternalError 		– внутренняя ошибка API.
		# AlreadyExistsInAuth – пользователь с таким MSISDN уже существует в auth-сервере.
		my $serviceData =  from_json($response->content,{ utf8  => 1 });
		foreach my $serviceDataTMP (keys %{$serviceData}) {
			if ($serviceDataTMP =~ /^status$/i) {
				return $self->analyzeBAPStatus($serviceData->{$serviceDataTMP},"add-user");
			}
		}
	}
	return undef;
}

# @tutorial Удаление абонента из системы
# @params Bigint $msisdn
#	<p>
#		Номер телефона абонента
#	<p>
# @params String $passwd
# @return
#	<p>
#		undef - ошибка выполнения
#		1 - операция выполнена успешно 
#	</p>

sub deleteUserAccaunt {
	my $self = shift;
	my $msisdn = shift;
	my $passwd = shift;

	if ((!defined $msisdn)||(!defined $passwd)) {
		$self->{error}->{text} 		= "Не задан один из обязательных параметров msisdn или puk";
		#$self->{error}->{status} 	= 404;
		$self->{error}->{status} 	= "WRONG FORMAT";
		return undef;
	}

	my $json = JSON->new->utf8;
	# Хеш для команды джейсона
#{
#  "command" : "auth",
#  "parameters" :
#  {
#    "login" : "79250012323",
#    "password" : "asd&asdf1"
#  }
#}
#а затем уже :
#{
#  "command" : "user",
#  "request" : "delete",
#  "parameters" : {
#    "session_id" : "1B2E898A8E05F607DEDF4315794F3949"
#  }
#}

	my $command = {};
	$command->{command} 		= "auth";
	$command->{parameters} 		= {};
	$command->{parameters}->{login} 	= "$msisdn";
	$command->{parameters}->{password} 	= $passwd;

	my $JSON = to_json($command,{pretty => 1});

	my $ua = LWP::UserAgent->new;
	$ua->timeout($self->{timeout});
	$ua->agent('HEX/1.1.0');
	$ua->local_address($LOCAL_ADDRESS);
	$ua->default_header('Accept-Language' => 'ru, en','Accept-Charset'  => 'utf-8;q=1, *;q=0.1');
	my $response = $ua->post($self->{url},
		Content_Type => 'application/json;charset=utf-8',
		Content => $JSON
	);

	$ua = undef;

	if (!$response->is_success) {
		# Http 404/403/500
		$self->{error}->{text} 		= "Первый запрос в платформу не выполнен ".$response->status_line();
		$self->{error}->{status} 	= $response->{_rc};
		return undef;
	} else {
		# Запрос выполнен успешно. Распарсить ответ в формате json
		# header 200
		# OK – команда выполнена удачно. В теле ответа уникальный идентификатор сессии.
		# 	session_id – уникальный идентификатор сессии.
		# 	TTL –  время жизни сессии. Указывает, до какого времени, в формате unix time, будет активная данная сессия. Данная значение зависит от установленного администратором системы времени жизни сессии.
		# WrongFormatError – ошибка составления запроса.
		# InternalError – внутренняя ошибка сервиса .
		# WrongAuthenticationParameters – не правильные данные для аутентификации или абонента не существует.
		my $serviceData =  from_json($response->content,{ utf8  => 1 });
		foreach my $serviceDataTMP (keys %{$serviceData}) {
			if ($serviceDataTMP =~ /^status$/i) {
				switch ($serviceData->{$serviceDataTMP}) {
					case "OK" {
						# Вытащить значения TTL и session_id
						if ((defined $serviceData->{result})&&(defined $serviceData->{result}->{session_id})) {
							# Выполнить запрос на удаление абонента из системы
							$command = {};
							$command->{command} 		= "user";
							$command->{request} 		= "delete";
							$command->{parameters} 		= {};
							$command->{parameters}->{session_id} 	= "$serviceData->{result}->{session_id}";

							my $JSON = to_json($command,{pretty => 1});

							my $ua = LWP::UserAgent->new;
							$ua->timeout($self->{timeout});
							$ua->agent('HEX/1.1.0');
							$ua->local_address($LOCAL_ADDRESS);
							$ua->default_header('Accept-Language' => 'ru, en','Accept-Charset'  => 'utf-8;q=1, *;q=0.1');
							my $response = $ua->post($self->{url},
								Content_Type => 'application/json;charset=utf-8',
								Content => $JSON
							);

							$ua = undef;
						
							if (!$response->is_success) {
								# Http 404/403/500
								$self->{error}->{text} 		= "Второй запрос в платформу не выполнен ".$response->status_line();
								$self->{error}->{status} 	= $response->{_rc};
								return undef;
							} else {
								# Запрос выполнен успешно. Распарсить ответ в формате json
								# header 200
								# OK – команда выполнена удачно. В теле ответа уникальный идентификатор сессии.
								# 	session_id – уникальный идентификатор сессии.
								# 	TTL –  время жизни сессии. Указывает, до какого времени, в формате unix time, будет активная данная сессия. Данная значение зависит от установленного администратором системы времени жизни сессии.
								# WrongFormatError – ошибка составления запроса.
								# InternalError – внутренняя ошибка сервиса .
								# WrongAuthenticationParameters – не правильные данные для аутентификации или абонента не существует.
								my $serviceData =  from_json($response->content,{ utf8  => 1 });
								foreach my $serviceDataTMP (keys %{$serviceData}) {
									if ($serviceDataTMP =~ /^status$/i) {
										return $self->analyzeBAPStatus($serviceData->{$serviceDataTMP},"user-delete");
									}
								}
							}
						} else {
							$self->{error}->{text} 		= "<auth> <user-delete> Неверный формат ответа от BAP";
							# $self->{error}->{status} 	= '500';
							$self->{error}->{status} 	= 'CRITICAL ERROR';
						}
						return 1;
					} else {
						return $self->analyzeBAPStatus($serviceData->{$serviceDataTMP},"auth");
					}
				}
			}
		}
	}
	return undef;
}

# @tutorial Удаление абонента из системы
# @params Bigint $msisdn
#	<p>
#		Номер телефона абонента
#	<p>
# @params String $passwd
# @return
#	<p>
#		undef - ошибка выполнения
#		1 - операция выполнена успешно 
#	</p>

sub deleteUserAccaunt_2 {
	my $self = shift;
	my $msisdn = shift;
	my $passwd = shift;

	if ((!defined $msisdn) || (!defined $passwd)) {
		$self->{error}->{text} 	 = "Не задан один из обязательных параметров msisdn или puk";
		$self->{error}->{status} = 404;
		return undef;
	}

	my $json = JSON->new->utf8;
	# Хеш для команды джейсона
	#{
	#  "command" : "auth",
	#  "parameters" :
	#  {
	#    "login" : "79250012323",
	#    "password" : "asd&asdf1"
	#  }
	#}
	#а затем уже :
	#{
	#	"command" : "user",
	#	"request" : "delete",
	#	"sudo"	  : $msisdn,
	#	"parameters" : {
	#		"session_id" : "1B2E898A8E05F607DEDF4315794F3949"
	#	}
	#}

	my $command = {};
	$command->{command} 	= "auth";
	$command->{parameters} 	= {};
	$command->{parameters}->{login} 	= "70000000000";
	$command->{parameters}->{password} 	= "48572913";

	my $JSON = to_json($command,{pretty => 1});

	my $ua = LWP::UserAgent->new;
	$ua->timeout($self->{timeout});
	$ua->agent('HEX/1.1.0');
	$ua->local_address($LOCAL_ADDRESS);
	$ua->default_header('Accept-Language' => 'ru, en','Accept-Charset'  => 'utf-8;q=1, *;q=0.1');
	my $response = $ua->post($self->{url},
		Content_Type => 'application/json;charset=utf-8',
		Content => $JSON
	);

	$ua = undef;

	if (!$response->is_success) {
		# Http 404/403/500
		$self->{error}->{text} 		= "Первый запрос в платформу не выполнен ".$response->status_line();
		$self->{error}->{status} 	= $response->{_rc};
		return undef;
	} else {
		# Запрос выполнен успешно. Распарсить ответ в формате json
		# header 200
		# OK – команда выполнена удачно. В теле ответа уникальный идентификатор сессии.
		# 	session_id – уникальный идентификатор сессии.
		# 	TTL –  время жизни сессии. Указывает, до какого времени, в формате unix time, будет активная данная сессия. Данная значение зависит от установленного администратором системы времени жизни сессии.
		# WrongFormatError – ошибка составления запроса.
		# InternalError – внутренняя ошибка сервиса .
		# WrongAuthenticationParameters – не правильные данные для аутентификации или абонента не существует.
		my $serviceData =  from_json($response->content,{ utf8  => 1 });
		foreach my $serviceDataTMP (keys %{$serviceData}) {
			if ($serviceDataTMP =~ /^status$/i) {
				switch ($serviceData->{$serviceDataTMP}) {
					case "OK" {
						# Вытащить значения TTL и session_id
						if ((defined $serviceData->{result})&&(defined $serviceData->{result}->{session_id})) {
							# Выполнить запрос на удаление абонента из системы
							$command = {};
							$command->{command} = "user";
							$command->{request} = "delete";
							$command->{sudo}	= $msisdn;
							$command->{parameters} = {};
							$command->{parameters}->{session_id} = "$serviceData->{result}->{session_id}";

							my $JSON = to_json($command,{pretty => 1});

							my $ua = LWP::UserAgent->new;
							$ua->timeout(20);
							$ua->agent('HEX/1.1.0');
							$ua->local_address($LOCAL_ADDRESS);
							$ua->default_header('Accept-Language' => 'ru, en','Accept-Charset'  => 'utf-8;q=1, *;q=0.1');
							my $response = $ua->post($self->{url},
								Content_Type => 'application/json;charset=utf-8',
								Content => $JSON
							);

							$ua = undef;

							if (!$response->is_success) {
								# Http 404/403/500
								$self->{error}->{text} 		= "Второй запрос в платформу не выполнен ".$response->status_line();
								$self->{error}->{status} 	= $response->{_rc};
								return undef;
							} else {
								# Запрос выполнен успешно. Распарсить ответ в формате json
								# header 200
								# OK – команда выполнена удачно. В теле ответа уникальный идентификатор сессии.
								# 	session_id – уникальный идентификатор сессии.
								# 	TTL –  время жизни сессии. Указывает, до какого времени, в формате unix time, будет активная данная сессия. Данная значение зависит от установленного администратором системы времени жизни сессии.
								# WrongFormatError – ошибка составления запроса.
								# InternalError – внутренняя ошибка сервиса .
								# WrongAuthenticationParameters – не правильные данные для аутентификации или абонента не существует.
								my $serviceData =  from_json($response->content,{ utf8  => 1 });
								foreach my $serviceDataTMP (keys %{$serviceData}) {
									if ($serviceDataTMP =~ /^status$/i) {
										return $self->analyzeBAPStatus($serviceData->{$serviceDataTMP},"delete-user-sudo");
									}
								}
							}
						} else {
							$self->{error}->{text} 		= "<auth> Неверный формат ответа от BAP";
							#$self->{error}->{status} 	= 500;
							$self->{error}->{status} 	= "CRITICAL ERROR";
						}
						return 1;
					}
					else {
						return $self->analyzeBAPStatus($serviceData->{$serviceDataTMP},"delete-user");
					}
				}
			}
		}
	}
	return undef;
}

# @tutorial Анализ статусов
# @params String $status
#	<p>
#		Буквенный статус ответа
#	<p>
# @params String $flag
#	<p>
#		Флаг, обозначающий операцию
#	<p>
# @return
#	<p>
#		undef - ошибка выполнения
#		1 - операция выполнена успешно 
#	</p>

sub analyzeBAPStatus {
	my $self	= shift;
	my $status	= shift;
	my $flag	= shift;

	if (!defined $flag) { $flag = "";}

	if (defined $status) {
		switch ($status) {
			case "OK" {
				return 1;
			}
			case "Accepted" {
				return 1;
			}
			case "WrongFormatError" {
				$self->{error}->{text} 		= "<bap> <$flag> Запрос в платформу не выполнен WrongFormatError. ";
				#$self->{error}->{status} 	= 404;
				$self->{error}->{status} 	= "WRONG FORMAT";
				#$self->{error}->{status} 	= "WrongFormatError";
			}
			case "WrongMsisdnError" {
				$self->{error}->{text} 		= "<bap> <$flag> Запрос в платформу не выполнен WrongMsisdnError";
				#$self->{error}->{status} 	= 404;
				$self->{error}->{status} 	= "WRONG FORMAT";
				#$self->{error}->{status} 	= "WrongMsisdnError";
			}
			case "WrongGroupError" {
				$self->{error}->{text} 		= "<bap> <$flag> Не указан идентификатор группы или указан неверный идентификатор группы Error";
				#$self->{error}->{status} 	= 404;
				$self->{error}->{status} 	= "WRONG FORMAT";
				#$self->{error}->{status} 	= "WrongGroupError";
			}
			case "WrongIPError" {
				$self->{error}->{text} 		= "<bap> <$flag> Запрос прислан не с того IP-адреса Error";
				#$self->{error}->{status} 	= 403;
				$self->{error}->{status} 	= "ACCESS DENIED";
				#$self->{error}->{status} 	= "WrongGroupError";
			}
			case "WrongPasswordError" {
				$self->{error}->{text} 		= "<bap> <$flag> Запрос в платформу не выполнен WrongPasswordError";
				#$self->{error}->{status} 	= 403;
				$self->{error}->{status} 	= "WRONG PASSWORD";
				#$self->{error}->{status} 	= "WrongPasswordError";
			}
			case "MWProblem-400" {
				$self->{error}->{text} 		= "<bap> <$flag> Запрос в платформу не выполнен MWProblem-400";
				#$self->{error}->{status} 	= 400;
				$self->{error}->{status} 	= "CRITICAL ERROR";
				#$self->{error}->{status} 	= "MWProblem-400";
			}
			case "MWProblem-403" {
				$self->{error}->{text} 		= "<bap> <$flag> Запрос в платформу не выполнен MWProblem-403";
				#$self->{error}->{status} 	= 403;
				$self->{error}->{status} 	= "ACCESS DENIED";
				#$self->{error}->{status} 	= "MWProblem-403";
			}
			case "MWProblem-404" {
				$self->{error}->{text} 		= "<bap> <$flag> Запрос в платформу не выполнен MWProblem-404";
				#$self->{error}->{status} 	= 404;
				$self->{error}->{status} 	= "WRONG FORMAT";
				#$self->{error}->{status} 	= "MWProblem-404";
			}
			case "MWProblem-500" {
				$self->{error}->{text} 		= "<bap> <$flag> Запрос в платформу не выполнен MWProblem-500";
				#$self->{error}->{status} 	= 500;
				$self->{error}->{status} 	= "CRITICAL ERROR";
				#$self->{error}->{status} 	= "MWProblem-500";
			}
			case "TooManyNewPasswordRequests" {
				$self->{error}->{text} 		= "<bap> <$flag> Сервер авторизации счел, что слишком много запросов на высылку нового пароля для MSISDN TooManyNewPasswordRequests";
				#$self->{error}->{status} 	= 500;
				$self->{error}->{status} 	= "TOO MANY TRIES";
				#$self->{error}->{status} 	= "TooManyNewPasswordRequests";
			}
			case "AlreadyExists" {
				$self->{error}->{text} 		= "<bap> <$flag> Пользователь уже существует AlreadyExists-171";
				#$self->{error}->{status} 	= 171;
				$self->{error}->{status} 	= "EXISTS";
				#$self->{error}->{status} 	= "AlreadyExists";
			}
			case "AlreadyExistsInAuth" {
				$self->{error}->{text} 		= "<bap> <$flag> Пользователь с таким MSISDN уже существует в auth-сервере";
				#$self->{error}->{status} 	= 171;
				$self->{error}->{status} 	= "EXISTS";
			}
			case "WrongAuthenticationParameters" {
				$self->{error}->{text} 		= "<bap> <$flag>  Запрос в платформу не выполнен WrongAuthenticationParameters";
				#$self->{error}->{status} 	= 403;
				$self->{error}->{status} 	= "ACCESS DENIED";
				#$self->{error}->{status} 	= "WrongAuthenticationParameters";
			}
			case "WrongSudoMsisdn" {
				$self->{error}->{text} 		= "<bap> <$flag> Абонента не найден в базе БАП";
				#$self->{error}->{status} 	= 404;
				$self->{error}->{status} 	= "NOT EXISTS";
			}
			case "PasswordExpired" {
				$self->{error}->{text} 		= "<bap> <$flag> Сервер авторизации сообщил, что время жизни пароля истекло и необходимо запросить новый пароль";
				#$self->{error}->{status} 	= 403;
				$self->{error}->{status} 	= "ACCESS DENIED";
			}
			case "BadPasswordPasswordChanged" {
				$self->{error}->{text} 		= "<bap> <$flag> Сервер авторизации сообщил, что передан неверный пароль доступа. Поскольку было выполнено уже 10 попыток неверной аутентификации, то пароль был сменен на автоматически сгенерированный";
				#$self->{error}->{status} 	= 403;
				$self->{error}->{status} 	= "ACCESS DENIED";
			}
			case "TempLocked" {
				$self->{error}->{text} 		= "<bap> <$flag> Сервер авторизации сообщил, что аккаунт времено заблокирован из-за попытки подбора пароля";
				#$self->{error}->{status} 	= 403;
				$self->{error}->{status} 	= "ACCESS DENIED";
			}
			case "BadPasswordLockTime" {
				$self->{error}->{text} 		= "<bap> <$flag> Передан неверный пароль доступа. Поскольку было выполнено уже 10 попыток неверной аутентификации и аккаунт заблокирован на 30 минут";
				#$self->{error}->{status} 	= 403;
				$self->{error}->{status} 	= "ACCESS DENIED";
			}
			case "WrongSessionError" {
				$self->{error}->{text} 		= "<bap> <$flag> Не правильный или отсутствующий идентификатор сессии";
				#$self->{error}->{status} 	= 404;
				$self->{error}->{status} 	= "WRONG FORMAT";
			}
			case "NotAllowedError" {
				$self->{error}->{text} 		= "<bap> <$flag> Действие запрещено. Возвращается, если у абонента не достаточно средств на счету для подписки на услугу или он заблокирован";
				#$self->{error}->{status} 	= 403;
				$self->{error}->{status} 	= "ACCESS DENIED";
			}
			case "NotAvaliableError" {
				$self->{error}->{text} 		= "<bap> <$flag> Действие недоступно";
				#$self->{error}->{status} 	= 403;
				$self->{error}->{status} 	= "ACCESS DENIED";
			}
			case "AllReadySubscribed" {
				$self->{error}->{text} 		= "<bap> <$flag> Пользователь уже подписан на данный пакет";
				#$self->{error}->{status} 	= 171;
				$self->{error}->{status} 	= "EXISTS";
			}
			case "WrongID" {
				$self->{error}->{text} 		= "<bap> <$flag> Не верный или отсутствующий идентификатор пакета";
				#$self->{error}->{status} 	= 404;
				$self->{error}->{status} 	= "WRONG FORMAT";
			}
			case "WrongChannelID" {
				$self->{error}->{text} 		= "<bap> <$flag> Один из переданных идентификаторов каналов не верен(При удаление канала из пакета)";
				#$self->{error}->{status} 	= 404;
				$self->{error}->{status} 	= "WRONG FORMAT";
			}
			case "WrongUserMsisdn" {
				$self->{error}->{text} 		= "<bap> <$flag> Неверный MSISDN пользователя";
				#$self->{error}->{status} 	= 404;
				$self->{error}->{status} 	= "WRONG FORMAT";
			}
			case "WrongMsisdn" {
				$self->{error}->{text} 		= "<bap> <$flag> Не верный или отсутствующий идентификатор абонента при запросе user_info";
				#$self->{error}->{status} 	= 404;
				$self->{error}->{status} 	= "WRONG FORMAT";
			}
			case "InternalError" {
				$self->{error}->{text} 		= "<bap> <$flag>  Запрос в платформу не выполнен InternalError";
				#$self->{error}->{status} 	= 500;
				$self->{error}->{status} 	= "CRITICAL ERROR";
			} else {
				$self->{error}->{text} 		= "<bap> <$flag> CRITICAL ERROR ".$status;
				#$self->{error}->{status} 	= 500;
				$self->{error}->{status} 	= "CRITICAL ERROR";
			}
		}
	}
	return undef;
}

1;