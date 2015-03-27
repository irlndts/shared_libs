#!/usr/bin/perl -w

# @copyright CQSpel 2011
# Class
# 	Класс обработки логов
#	Добавляет информацию в системные лог файлы, извлекает статистику по: msisdn,дате и времени,протоколу работы,
#	типу сценария обработки
# @since
#	1.5
#		Перевод на singleton

package Logs;
use strict;
use locale;
use Sys::Syslog qw (:standard :macros);
use Switch;
use Text::Iconv;

	# Количество созданных экземпляров класса
	my $count 	= 0;
	my $VERTION = 1.5;

	# Объект вывода логов
	my $Logs;

	# Конструктор
	sub new {
		my $proto = shift;
		# Конфигурационный файл
		my $conf = shift;
		my $class = ref($proto) || $proto;
		$count++;
		my $self = {};

		if (defined $conf->{productName}) {
			openlog $conf->{productName}, "ndelay,pid", LOG_LOCAL0;
			$self = {LOG => $conf->{productName}};
		} else {
			openlog 'VMP', "ndelay,pid", LOG_LOCAL0;
			$self->{LOG} = undef;
		}

		# Конфигурационный файл
		$self->{conf} 	= $conf;

		# Массив ошибок (для отладки)
		$self->{errors} 	= {};

		# инициализация ссылки на класс (объект)
		return $Logs ||= bless ($self,$class);
	}

	sub DESTROY {
		my $self = shift;
		
		#print "Destroy ".ref($self)." count = $count \n";
		$count--;
	}

	# Вывод в лог файл, если включен режим дебага
	# @param String type
	#	<p>Тип вывода</p>
	# @param String str
	#	<p>Строка сообщения, которую необходимо добавить в вывод</p>
	# @param Array args
	#	<p>Дополнительные параметры вывода</p>
	# @return
	#	<p>
	#		undef 	- выключен режим дебага
	#		1		- режим дебага включен и запись в лог файл выполнена
	#	</p>
	sub sysLog {
		my ($self,$type,$str,@args) = @_;
		$str = $str || 'Not Defined';
		if ((defined $self->{conf})&&(defined $self->{conf}->{debug})){
			if ($self->{conf}->{debug} eq 1) {
				if (defined $self->{conf}->{logCharset}) {
					if (!my $type =~ /utf-8/i) {
						my $conv = Text::Iconv->new("UTF-8",$self->{conf}->{logCharset});
						$str = $conv->convert($str);
					}
				}

				# Добавить название лога в вывод
				my $addStr;
				$addStr = " ".$self->{LOG} if defined $self->{LOG};
				$addStr .= " ".$self->{conf}->{VERSION};

				# Вывод информации в логи в транслите
				if (defined $self->{conf}->{logTranslit} && defined $str) {
					my $strTmp = $self->translitIt($str);
					if (defined $strTmp) {
						$str = $strTmp;
					}
				}

				switch ($type) {
					case "notice" {
						if (scalar(@args) > 0) {
							syslog(LOG_INFO,$addStr." NOTICE: ".$str,@args);
						} else {
							syslog(LOG_INFO,$addStr." NOTICE: ".$str);
						}
					}
					case "error" {
						if (scalar(@args) > 0) {
							syslog(LOG_INFO,$addStr." ERROR: ".$str,@args);
						} else {
							syslog(LOG_INFO,$addStr." ERROR: ".$str);
						}
					}
					case "warning" {
						if (scalar(@args) > 0) {
							syslog(LOG_INFO,$addStr." WARNING: ".$str,@args);
						} else {
							syslog(LOG_INFO,$addStr." WARNING: ".$str);
						}
					}
					else {
						if (scalar(@args) > 0) {
							syslog(LOG_INFO,$addStr." ALERT: ".$str,@args);
						} else {
							syslog(LOG_INFO,$addStr." ALERT: ".$str);
						}
					}
				}
			} else {
				return undef;
			}
		}
		return 1;
	}

	# Преобразует русский текст в транслит
	# @param String str
	#	<p>текст, который необходимо преобразовать</p>
	# @return
	#	<p>
	#		undef 	- не удалось преобразовать
	#		str		- преобразование прошло успешно
	#	</p>
	sub translitIt{
		my ($self,$translit) = @_;
		$translit =~ s/ё/yo/g;
		$translit =~ s/Ё/YO/g;
		$translit =~ s/ж/zh/g;
		$translit =~ s/Ж/ZH/g;
		$translit =~ s/ч/ch/g;
		$translit =~ s/Ч/CH/g;
		$translit =~ s/ш/sh/g;
		$translit =~ s/Ш/SH/g;
		$translit =~ s/щ/shh/g;
		$translit =~ s/Щ/SHH/g;
		$translit =~ s/ъ//ig;
		$translit =~ s/ы/ii/g;
		$translit =~ s/Ы/II/g;
		$translit =~ s/ь//ig;
		$translit =~ s/э/ie/g;
		$translit =~ s/Э/IE/g;
		$translit =~ s/ю/yu/g;
		$translit =~ s/Ю/YU/g;
		$translit =~ s/я/ya/g;
		$translit =~ s/Я/YA/g;
		
		my %words = (
			"А" => "A",
			"а" => "a",
			"Б" => "B",
			"б" => "b",
			"В" => "V",
			"в" => "v",
			"Г" => "G",
			"г" => "g",
			"Д" => "D",
			"д" => "d",
			"Е" => "E",
			"е" => "e",
			"З" => "Z",
			"з" => "z",
			"И" => "I",
			"и" => "i",
			"Й" => "J",
			"й" => "j",
			"К" => "K",
			"к" => "k",
			"Л" => "L",
			"л" => "l",
			"М" => "M",
			"м" => "m",
			"Н" => "N",
			"н" => "n",
			"О" => "O",
			"о" => "o",
			"П" => "P",
			"п" => "p",
			"Р" => "R",
			"р" => "r",
			"С" => "S",
			"с" => "s",
			"Т" => "T",
			"т" => "t",
			"У" => "U",
			"у" => "u",
			"Ф" => "F",
			"ф" => "f",
			"Х" => "X",
			"х" => "x",
			"Ц" => "C",
			"ц" => "c"
		);

		foreach my $rusWord (keys %words) {
			$translit =~ s/$rusWord/$words{$rusWord}/g;
		}

		return $translit;
	}
1;
