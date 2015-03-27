#!/usr/bin/perl -w

# @tutorial Class фукнции для работы с деф-кодами
# @version 0.1
# @copyright apiskun 27-29.06.2012
# @since
#	0.1.1
#		Добавлены обработчики ошибок
#       0.1
#               Создание модуля
#		Функция readDefCodes
#		Функция searchOperator
#		Функция updateDefCodes
#

package def_codes;

use strict;
use utf8;
use Encode;
use DBI;
use Spreadsheet::ParseExcel;
use Spreadsheet::ParseExcel::FmtUnicode;
use Text::Iconv;
use Unicode::Map;


# Функция обновления def кодов из файла xml
# @param descriptor dbh
#   <p>Дескриптор ДБ</p>
# @param @string file
#   <p>путь к файлу xml</p>
# @return int
#   <p>
#	1 - все в порядке
#	0 - обновление прошло с ворнингами
#	-1- файл не существует
#	-2- не удалось отпарсить файл
#	-3- не удалось подключиться к БД
#   </p>
sub updateDefCodes {
	my ($dbh)  = shift;
	my ($file) = shift;
	my ($sth, @sqldata);
	my $iconv = Text::Iconv->new("CP1251","UTF-8");
	my $warning;

	#$dbh=$dbh || DBI->connect("dbi:Pg:host=192.168.173.14 dbname=subscriptions", 'postgres', '', {AutoCommit => 1});
	unless($dbh){
		print "Error: Can't open database: $DBI::errstr\n";
		return -3;
	}
	

	#Если файл не существует
	unless (-e $file) {
		print "Error: file $file doesn't exist\n";
		return -1;
	}

	my ($msisdn_start,$msisdn_stop);
	my $parser 	= Spreadsheet::ParseExcel->new();
	my $oFmtR 	= Spreadsheet::ParseExcel::FmtUnicode->new(Unicode_Map => "CP1251");
	my $workbook;
	$workbook 	= $parser->Parse($file,$oFmtR) or return -2;
	

	my %opers = (
		encode("utf8","СЗФ")             => "3",
		encode("utf8","Столичный")       => "1",
		encode("utf8","Сибирский")       => "5",
		encode("utf8","Центральный")     => "6",
		encode("utf8","Кавказский")      => "11",
		encode("utf8","Поволжский")      => "7",
		encode("utf8","Уральский")       => "4",
		encode("utf8","Дальневосточный") => "9"
	);
	my %columns = (
		encode("utf8","Код зоны  нумерации") => "code",
		encode("utf8","Начало диапазона")    => "def_start",
		encode("utf8","Окончание диапазона") => "def_stop",
		encode("utf8","Местоположение")      => "region"
	);
	
	# Если больше одного листа в документе
	if(scalar($workbook->worksheets())>0){
		# Получить текущее занчение даты и времени на сервере баз данных
		$sth = $dbh->prepare("SELECT now();");
		$sth->execute();
		my ($dataSTART) = $sth->fetchrow_array();
		unless($dataSTART){
			print "Warn: Can't get operation time\n";
		}

		my $i = 0;
		for my $worksheet ( $workbook->worksheets() ) {
			#print '|'.$iconv->convert($worksheet->{Name}).'|'.$opers{$iconv->convert($worksheet->{Name})}.'|';
			my ($row_min, $row_max) = $worksheet->row_range();
			my ($col_min, $col_max) = $worksheet->col_range();
			
			#print "    rows: ".$row_min."->".$row_max."; columns: ".$col_min."->".$col_max." \n";
=pod
			for my $col ($col_min .. $col_max){
				my $cell = $worksheet->get_cell($row_min, $col);
	            		next unless $cell;
	            		next unless $iconv->convert($cell->value());
	            		print "		col: ".$col." ";
	            		print " value: |".$columns{$iconv->convert($cell->value())}.'|'." \n";
			}
=cut
			for my $row (($row_min+1) .. $row_max) {
				my ($code, $def_start, $def_stop, $region) = ();
				$code 		= $worksheet->get_cell($row,0);
				$def_start 	= $worksheet->get_cell($row,1);
				$def_stop 	= $worksheet->get_cell($row,2);
				$region 	= $worksheet->get_cell($row,3);
				next unless $code;
				my $def_startTMP = undef;
				if ($def_start->value() eq 0) {
					$def_startTMP = "0000000";
				}
				next unless $iconv->convert($code->value());
				next unless $def_start;
				if(!defined $def_startTMP){
					next unless $iconv->convert($def_start->value());
					$def_start = $iconv->convert($def_start->value());
				} else {
					$def_start = $def_startTMP;
				}
				next unless $def_stop;
				next unless $iconv->convert($def_stop->value());
	
				$code = $iconv->convert($code->value());
				# $def_start = $iconv->convert($def_start->value());
				$def_stop = $iconv->convert($def_stop->value());
				$region = $iconv->convert($region->value());
				# Выравнивание до 7-ми символов, так как некоторые поля имеют не строковое форматирование, а числовое
				if(length($def_stop)<7){
					for(my $i=length($def_stop);$i<7;$i++){
						$def_stop = '0'.$def_stop;
					}
				}
				if(length($def_start)<7){
					for(my $i=length($def_start);$i<7;$i++){
						$def_stop = '0'.$def_start;
					}				
				}
				
				#print "Check: ".$code." - ".$def_start." - ".$def_stop." - ".$region." \n";
	
				if($opers{$iconv->convert($worksheet->{Name})}){
					# Проверить, есть ли такое значение в базе данных
					$sth = $dbh->prepare("SELECT *  FROM code_zones WHERE code = ? and def_start = ? and def_stop = ?;") or $warning=1;
					$code 		=~ s/\'//g;
					$def_start 	=~ s/\'//g;
					$def_stop 	=~ s/\'//g;
	
					$sth->execute($code,$def_start,$def_stop);
					my $found = 0;
					while (@sqldata = $sth->fetchrow_array()) {
						if(@sqldata) {
							#print "\tExists: ".$code." - ".$def_start." - ".$def_stop." - ".$region." \n";
							# Обновить поле изменения
							$sth = $dbh->prepare("UPDATE code_zones set change_date = now() WHERE id = ?;");
							unless($sth->execute($sqldata[0])){
								print "Warn: Can't updata code_zones for $sqldata[0]: $DBI::errstr\n";
								$warning=1;
							}
							$found = 1;
							last;
						};
					}
					if($found eq 0){
#						print "\tNew".$code." - ".$def_start." - ".$def_stop." - ".$region." \n";
						# Сделать вставку новой строки в базу данных
						$msisdn_start="7$code$def_start";
						$msisdn_stop ="7$code$def_stop";
						$sth = $dbh->prepare("INSERT INTO code_zones (code,def_start,def_stop,region,oper,change_date,msisdn_start,msisdn_stop) VALUES (?,?,?,?,?,now(),?,?);");
						unless($sth->execute($code,$def_start,$def_stop,$region,$opers{$iconv->convert($worksheet->{Name})},$msisdn_start,$msisdn_stop)){
							print "Warn: Can't insert into code_zones code $code: $DBI::errstr\n";
							$warning=1;
						}
					}
				}
			}
			$i++; 
		}
		# Удалить все записи из деф кодов, которых нет в файле и для которых есть переопределение старта и конца
		$sth = $dbh->prepare("
				SELECT * FROM code_zones WHERE id in 
				(
					SELECT cz.id 
					FROM code_zones as cz 
					WHERE
						(cz.change_date < now() or cz.change_date is null)
						and 
						(
							(
							SELECT count(id) 
							FROM code_zones 
							WHERE 
								(def_start = cz.def_start or def_stop = cz.def_stop)
								and code = cz.code
								and id <> cz.id
							) >= 2 
							or 
							(
							SELECT count(id) 
							FROM code_zones 
							WHERE 
								(def_start = cz.def_start or def_stop = cz.def_stop)
								and code = cz.code
								and id <> cz.id
								and cz.def_start = cz.def_stop
							) = 1
						)
					)");
		$sth->execute();
		my $ssth=$dbh->prepare("delete from code_zones where code=? and (def_start=? or def_stop=?) and id <> ?");
		while (@sqldata = $sth->fetchrow_array()) {
			unless($ssth->execute($sqldata[1],$sqldata[2],$sqldata[3],$sqldata[0])){
				print "Warn: Can't delete dublicated values from code_zones: $DBI::errstr\n";
				$warning=1;
			}
		}
		$sth=$dbh->prepare("delete from code_zones where change_date < ?") or $warning=1;
		unless($sth->execute($dataSTART)){
			print "Warn: Can't delete old values from code_zones: $DBI::errstr\n";
			$warning=1;
		}
	}
	$warning?(return 0):(return 1);
}


# Функция обновления def кодов из файла xml для нового CMS
# @param descriptor dbh
#   <p>Дескриптор ДБ</p>
# @param @string file
#   <p>путь к файлу xml</p>
# @return int
#   <p>
#	1 - все в порядке
#	0 - обновление прошло с ворнингами
#	-1- файл не существует
#	-2- не удалось отпарсить файл
#	-3- не удалось подключиться к БД
#   </p>
sub updateDefCodesCms {
	my ($dbh)  = shift;
	my ($file) = shift;
	my ($sth, @sqldata);
	my $iconv = Text::Iconv->new("CP1251","UTF-8");
	my $warning;

	#$dbh=$dbh || DBI->connect("dbi:Pg:host=192.168.173.14 dbname=subscriptions", 'postgres', '', {AutoCommit => 1});
	unless($dbh){
		print "Error: Can't open database: $DBI::errstr\n";
		return -3;
	}
	

	#Если файл не существует
	unless (-e $file) {
		print "Error: file $file doesn't exist\n";
		return -1;
	}

	my ($msisdn_start,$msisdn_stop);
	my $parser 	= Spreadsheet::ParseExcel->new();
	my $oFmtR 	= Spreadsheet::ParseExcel::FmtUnicode->new(Unicode_Map => "CP1251");
	my $workbook;
	$workbook 	= $parser->Parse($file,$oFmtR) or return -2;
	

	my %opers = (
		encode("utf8","СЗФ")             => "3",
		encode("utf8","Столичный")       => "1",
		encode("utf8","Сибирский")       => "5",
		encode("utf8","Центральный")     => "6",
		encode("utf8","Кавказский")      => "11",
		encode("utf8","Поволжский")      => "7",
		encode("utf8","Уральский")       => "4",
		encode("utf8","Дальневосточный") => "9"
	);
	my %columns = (
		encode("utf8","Код зоны  нумерации") => "code",
		encode("utf8","Начало диапазона")    => "def_start",
		encode("utf8","Окончание диапазона") => "def_stop",
		encode("utf8","Местоположение")      => "region"
	);
	
	# Если больше одного листа в документе
	if(scalar($workbook->worksheets())>0){
		# Получить текущее занчение даты и времени на сервере баз данных
		$sth = $dbh->prepare("SELECT now();");
		$sth->execute();
		my ($dataSTART) = $sth->fetchrow_array();
		unless($dataSTART){
			print "Warn: Can't get operation time\n";
		}

		my $i = 0;
		for my $worksheet ( $workbook->worksheets() ) {
			#print '|'.$iconv->convert($worksheet->{Name}).'|'.$opers{$iconv->convert($worksheet->{Name})}.'|';
			my ($row_min, $row_max) = $worksheet->row_range();
			my ($col_min, $col_max) = $worksheet->col_range();
			
			#print "    rows: ".$row_min."->".$row_max."; columns: ".$col_min."->".$col_max." \n";
=pod
			for my $col ($col_min .. $col_max){
				my $cell = $worksheet->get_cell($row_min, $col);
	            		next unless $cell;
	            		next unless $iconv->convert($cell->value());
	            		print "		col: ".$col." ";
	            		print " value: |".$columns{$iconv->convert($cell->value())}.'|'." \n";
			}
=cut
			for my $row (($row_min+1) .. $row_max) {
				my ($code, $def_start, $def_stop, $region) = ();
				$code 		= $worksheet->get_cell($row,0);
				$def_start 	= $worksheet->get_cell($row,1);
				$def_stop 	= $worksheet->get_cell($row,2);
				$region 	= $worksheet->get_cell($row,3);
				next unless $code;
				my $def_startTMP = undef;
				if ($def_start->value() eq 0) {
					$def_startTMP = "0000000";
				}
				next unless $iconv->convert($code->value());
				next unless $def_start;
				if(!defined $def_startTMP){
					next unless $iconv->convert($def_start->value());
					$def_start = $iconv->convert($def_start->value());
				} else {
					$def_start = $def_startTMP;
				}
				next unless $def_stop;
				next unless $iconv->convert($def_stop->value());
	
				$code = $iconv->convert($code->value());
				# $def_start = $iconv->convert($def_start->value());
				$def_stop = $iconv->convert($def_stop->value());
				$region = $iconv->convert($region->value());
				# Выравнивание до 7-ми символов, так как некоторые поля имеют не строковое форматирование, а числовое
				if(length($def_stop)<7){
					for(my $i=length($def_stop);$i<7;$i++){
						$def_stop = '0'.$def_stop;
					}
				}
				if(length($def_start)<7){
					for(my $i=length($def_start);$i<7;$i++){
						$def_stop = '0'.$def_start;
					}				
				}
				
				#print "Check: ".$code." - ".$def_start." - ".$def_stop." - ".$region." \n";
	
				if($opers{$iconv->convert($worksheet->{Name})}){
					# Проверить, есть ли такое значение в базе данных
					$sth = $dbh->prepare("SELECT *  FROM code_zones WHERE code = ? and def_start = ? and def_stop = ?;") or $warning=1;
					$code 		=~ s/\'//g;
					$def_start 	=~ s/\'//g;
					$def_stop 	=~ s/\'//g;
	
					$sth->execute($code,$def_start,$def_stop);
					my $found = 0;
					while (@sqldata = $sth->fetchrow_array()) {
						if(@sqldata) {
							#print "\tExists: ".$code." - ".$def_start." - ".$def_stop." - ".$region." \n";
							# Обновить поле изменения
							$sth = $dbh->prepare("UPDATE code_zones set change_date = now() WHERE id = ?;");
							unless($sth->execute($sqldata[0])){
								print "Warn: Can't updata code_zones for $sqldata[0]: $DBI::errstr\n";
								$warning=1;
							}
							$found = 1;
							last;
						};
					}
					if($found eq 0){
#						print "\tNew".$code." - ".$def_start." - ".$def_stop." - ".$region." \n";
						# Сделать вставку новой строки в базу данных
						$msisdn_start="7$code$def_start";
						$msisdn_stop ="7$code$def_stop";
						$sth = $dbh->prepare("INSERT INTO code_zones (code,region,id_operator_branch_region,change_date,msisdn_start,msisdn_stop) VALUES (?,?,?,now(),?,?);");
						unless($sth->execute($code,$region,$opers{$iconv->convert($worksheet->{Name})},$msisdn_start,$msisdn_stop)){
							print "Warn: Can't insert into code_zones code $code: $DBI::errstr\n";
							$warning=1;
						}
					}
				}
			}
			$i++; 
		}
		# Удалить все записи из деф кодов, которых нет в файле и для которых есть переопределение старта и конца
		$sth = $dbh->prepare("
				SELECT id, code, msisdn_start, msisdn_stop FROM code_zones WHERE id in 
				(
					SELECT cz.id 
					FROM code_zones as cz 
					WHERE
						(cz.change_date < now() or cz.change_date is null)
						and 
						(
							(
							SELECT count(id) 
							FROM code_zones 
							WHERE 
								(msisdn_start = cz.msisdn_start or msisdn_stop = cz.msisdn_stop)
								and code = cz.code
								and id <> cz.id
							) >= 2 
							or 
							(
							SELECT count(id) 
							FROM code_zones 
							WHERE 
								(msisdn_start = cz.msisdn_start or msisdn_stop = cz.msisdn_stop)
								and code = cz.code
								and id <> cz.id
								and cz.msisdn_start = cz.msisdn_stop
							) = 1
						)
					)");
		$sth->execute();
		my $ssth=$dbh->prepare("delete from code_zones where code=? and (msisdn_start=? or msisdn_stop=?) and id <> ?");
		while (@sqldata = $sth->fetchrow_array()) {
			unless($ssth->execute($sqldata[1],$sqldata[2],$sqldata[3],$sqldata[0])){
				print "Warn: Can't delete dublicated values from code_zones: $DBI::errstr\n";
				$warning=1;
			}
		}
		$sth=$dbh->prepare("delete from code_zones where change_date < ?") or $warning=1;
		unless($sth->execute($dataSTART)){
			print "Warn: Can't delete old values from code_zones: $DBI::errstr\n";
			$warning=1;
		}
	}
	$warning?(return 0):(return 1);
}


# Функция поиска диапазона, в который входит msisdn
# @param string $msisdn
#   <p>Номер абонента</p>
# @param @href def_codes
#   <p> Массив ссылок на дэф-коды</p>
# @return hash
#   <p>
#	Ссылка на данные об операторе, которому принадлежит msisdn
#   </p>


sub searchOperator {
	
	my $msisdn = shift;
	my $dc = shift;
	my @def_codes = @{$dc};
	my $r;
	my $start = int($#def_codes / 2);
	my $delta = $start;
	
	if (int($delta/2)*2 != $delta) {
		$delta = int($delta/2)+1;
	} else {
		$delta = int($delta/2);
	};

	my $finished = 0;
	my $lastdelta = -1;
	my $needexit = 0;

	# Ограничитель на количество итераций алгоритма (для обработки отсутствующих диапазонов)
	my $limitcount = 100;
	
	#поиск нужного диапазона
	while ( 1 ) {
		if (($start + $delta) < 0) {last;};
		if (($start + $delta - 1) > $#def_codes) {last;};
		my $cur = $def_codes[$start];
		if (($msisdn >= $cur->{msisdn_start}) && ($msisdn <= $cur->{msisdn_stop})) {
			$r = $cur;
			last;
		} elsif ($msisdn < $cur->{msisdn_start}) {
			$start -= $delta;
		} else {
			$start += $delta;
		};

		if (int($delta/2)*2 != $delta) {
			$delta = int($delta/2)+1;
		} else {
			$delta = int($delta/2);
		};
		if ($delta <= 0) {last;};
		if ($limitcount-- <= 0) {
			undef($r);
			last;
		};
	};
	return($r);
}

# Чтение списка DEF кодов
# @param href $dba
#   <p>Ссылка на БД</p>
# @return @hash
#   <p>
#	Массив ссылок на дэф-коды
#   </p>

sub readDefCodes {
	my ($dbh) = shift;
	
	unless ($dbh){
		print "Error: Can't connect to DB: $DBI::errstr\n";
		return undef;
	}
	my @def_codes=();

	# Берем из БД
	my $c = $dbh->prepare('select * from code_zones order by code,def_start');
	$c->execute();
	while (my $r = $c->fetchrow_hashref()) {
		push(@def_codes, $r);
	};
	$c->finish;

	return @def_codes;
};



#my $dbh = DBI->connect("dbi:Pg:host=192.168.173.14 dbname=subscriptions","postgres","",{AutoCommit => 1}) or die "DBI error: $!\n";
#my @responses = readDefCodes ($dbh);
#my $r = searchOperator("79261154776",@responses);
#foreach (keys %{$r}){
#	print "\t$_ = ".$r->{$_}."\n";
#}
#print  updateDefCodes($dbh,"file.xls");


# Определяет внутренний идентификатор региона по номеру телефона абонента
# @param Bigint $msisdn
# <p>Номер телефона абонента</p>
# @return
#       <p>
#               undef - не удалось определить код региона
#               N - код региона
#       </p>
sub _operByDefCode {
	my ($msisdn, $defcodes) = @_;
	my $code = substr($msisdn,1,3);
	my $sub_code = substr($msisdn,4,7);
	foreach my $def (@{$defcodes->{$code}}) {
		if (($def->{def_start} <= $sub_code) && ($def->{def_stop} >= $sub_code)) {
			return($def->{oper});
		};
	};
	return(undef);
};


#Получаем список def_codes
# @param $dbh
# коннект к базе данных
# $return
#	<p>
#		$defcodes
#	</p>
sub _getDefCodes {
	my ($dbh) = shift;
	my $sth;
	my $defcodes;
	unless ($sth = $dbh->prepare('select * from code_zones')) {
		$sth->finish();
		return undef;	
	};
	unless ($sth->execute()){
		$sth->finish();
		return undef;
	};
	while (my $def = $sth->fetchrow_hashref()) {
		if (!defined($defcodes->{$def->{code}}) || (ref($defcodes->{$def->{code}}) ne 'ARRAY')) {
			$defcodes->{$def->{code}} = [];
		};
		push(@{$defcodes->{$def->{code}}}, $def);
	};
	$sth->finish;
	$dbh->commit;
	$dbh->disconnect;
	return $defcodes;
}

1;

