package oauths;

use strict;
use DBI;
use Cache::Memcached;
use POSIX;
use utf8;
use Encode;

sub get_token_auth {
	my ($dbh, $memc, $tokenstr) = @_;

	my $token = mc::get($memc, 'token_auth', $tokenstr);
	if (!defined($token) || ($token eq '')) {
		my $c = $dbh->prepare('select * from tokens_auth where token = ? and create_time >= (now() - \'10 minutes \'::interval) order by create_time desc limit 1');
		$c->execute($tokenstr);
		# Если строк нет, вернуть undef
		if ($c->rows()< 1) {return undef;};
		$token = $c->fetchrow_hashref();
		$c->finish;
		$dbh->commit;
		
		mc::set($memc, 'token_auth', $tokenstr, $token, 300) if defined($token);
	};
	return($token);
};

sub get_token_access {
	my ($dbh, $memc, $tokenstr, $clientstr) = @_;

	my $token = mc::get($memc, 'token_access', $tokenstr);
	if (!defined($token) || ($token eq '')) {
		my $sql;
		my @prms;
		if (defined($clientstr) && ($clientstr ne '')) {
			$sql = 'select * from tokens_access where client = ? and token = ? and ttl > now() limit 1';
			push(@prms, $clientstr);
			push(@prms, $tokenstr);
		} else {
			$sql = 'select * from tokens_access where token = ? and ttl > now() limit 1';
			push(@prms, $tokenstr);
		};
		my $c = $dbh->prepare($sql);
		$c->execute(@prms);
		$token = $c->fetchrow_hashref();
		$c->finish;
		$dbh->commit;
	
		mc::set($memc, 'token_access', $tokenstr, $token) if defined($token);
	};
	return($token);
};

sub get_client {
	my ($dbh, $memc, $clientstr, $protocol) = @_;
# по умолчанию выбираем OAuth протокол
	$protocol ||= 'oauth';
	my $client = mc::get($memc, 'client', $clientstr);
	
	if (!defined($client) || ($client eq '')) {
		my $c = $dbh->prepare('select * from clients where id = ?');
		$c->execute($clientstr);
		$client = $c->fetchrow_hashref();
		$dbh->commit;
	
=version before JWT
		# Извлекаем ресурсы в строку формата массива postgres
		my @res;
		$c = $dbh->prepare('select res_id from clients_resources where client_id = ?');
		$c->execute($clientstr);
		while (my ($r) = $c->fetchrow_array()) {
			push(@res, $r);
		};
=cut	
		if ($protocol eq 'jwt') {
			$client->{resources} = getResourcesByPartnerProtocol($dbh, $clientstr, $protocol);
		}
		elsif ($protocol eq 'oauth') {
			my @res;
			$c = $dbh->prepare('select res_id from clients_resources where client_id = ?');
			$c->execute($clientstr);
			while (my ($r) = $c->fetchrow_array()) {
				push(@res, $r);
			};
			$client->{resources} = \@res;	
		}
	
		mc::set($memc, 'client', $clientstr, $client, 300) if defined($client);
		#mc::set($memc, 'client1', $clientstr, $client, 300) if defined($client);
	};
	
	return($client);
};


# получение доступных ресурсов для данного партнера по данному протоколу

# INPUT:
# dbh - соединение с БД OAuth
# partnerId - id партнера, характеризующий контекст поступившего запроса. это может быть проект "Расширение браузера chromium" или партнер Yandex
# protocol - протокол ,по которому происходит авторизацуия. jwt или OAuth

#OUTPUT: 
# resources - ARRAYREF, содержащий список полученных ресурсов. Пример: [MSISDN,SUB]
sub getResourcesByPartnerProtocol {
	my $dbh = shift;
	my ($partnerId, $protocol) = @_;
	my $resources = [];
	my $req = qq{
		SELECT r.*
  			FROM resources r 
			  JOIN protocols_resources pr ON r.id = pr.resource_id
			  JOIN protocols p ON pr.protocol_id = p.id
			  JOIN clients_resources cr ON r.id = cr.res_id
			WHERE p.alias = ?
				AND cr.client_id = ?;
	};
	my $sth = $dbh->prepare($req);
	$sth->execute($protocol, $partnerId);
	while (my $row = $sth->fetchrow_hashref) {
		push @$resources, $row->{id};
	};
	$sth->finish;
	$dbh->commit;
	return $resources;
};

1;
