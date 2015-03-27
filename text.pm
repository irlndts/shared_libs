#!/usr/bin/perl -w

# @tutorial Class фукнции для работы с текстом
# @version 0.1
# @copyright cqspel 02.07.2012
# @since
#       0.2
#               Создание шинглов и их обработка
#       0.1
#               Транслитирация. Внимане! передаваемый текст должне быть в utf-8

package text;

use strict;
use utf8;
use Encode;
use vars qw($stopSymbols $length @stopSymbols);

	# Размер группы слов
	my $length;
	# Символы конца/начала слова (удаляемые из текста)
	my  @stopSymbols = (".",",","!","?",":",";","-","–","n","r","(",")","<",">","/","\\","{","}","[","]","#");
	# Слова и части речи, котоыре не будут участвовать в анализе схожести
	my @stopWords = ('это', 'как', 'так', 'и', 'в', 'над', 'к', 'до', 'не', 'на', 'но', 'за', 'то', 'с', 'ли', 'а', 'во', 'от', 'со', 'для', 'о', 'же', 'ну', 'вы', 'бы', 'что', 'кто', 'он', 'она','они','оно','я','мы','ты','из');

# @param String str
#	<p>текст, который необходимо преобразовать</p>
# @return
#	<p>
#		undef 	- не удалось преобразовать
#		str		- преобразование прошло успешно
#	</p>
sub stringToTranslit{
	my $translit = shift;
	my %words = (
			"ё" => "yo",
			"Ё" => "yo",
			"ж" => "zh",
			"Ж" => "Zh",
			"ч" => "ch",
			"Ч" => "Ch",
			"ш" => "sh",
			"Ш" => "Sh",
			"щ" => "shh",
			"Щ" => "Shh",
			"ы" => "ii",
			"Ы" => "Ii",
			"э" => "ie",
			"Э" => "Ie",
			"ю" => "yu",
			"Ю" => "Yu",
			"я" => "ya",
			"Я" => "Ya"
	);

	$translit =~ y/АаБбВвГгДдЕеЗзИиЙйКкЛлМмНнОоПпРрСсТтУуФфХхЦцьъ/AaBbVvGgDdEeZzIiJjKkLlMmNnOoPpRrSsTtUuFfXxCc' /;
	foreach my $rusWord (keys %words) {
		$translit =~ s/$rusWord/$words{$rusWord}/g;
	}

	return $translit;
}

# @param String str
#	<p>текст, который необходимо преобразовать</p>
# @return
#	<p>
#		undef 	- не удалось преобразовать
#		str		- преобразование прошло успешно
#	</p>


1;