package JWT::Client;

use strict;

# получить данные о клиенте по id, переданному в запросе.
sub get_client {
	my $clientId = shift;
# пока захардкодим. потом определимся с конечным вариантом и внесем 
	my $clients = {
		ext001 => {
			description 	=>	'расширение браузера',
			limit_by_url 	=> 	0,
			limit_by_ip 	=>	0,
			client_secret	=>	"kd94hf93k423kf44",
			active 			=> 	1,
			status			=> 	1,
			resources		=> 	{
				BAL 	=> 	1,
				MSISDN 	=> 	1,
				NODEF	=> 	1,
			},
		},
	};
	return $clients->{$clientId} || {resources => {} };
};


1;