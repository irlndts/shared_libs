#!/usr/bin/perl -w

# @tutorial Class системные функции
# @version 0.2
# @copyright cqspel 30.09.2012
# @since
#       0.2
#               Запись в сислог toSyslog
#       0.1
#               Открытие системного лога openLog

package sys;

use strict;
use POSIX;
use Sys::Syslog;
use Encode;

use lib qw(/home/projects/SHARED_API);
use text;

# Открывает вывод в лог
# @param String $logname
#	- ident лога
# @param String $facility
#	- По умолчанию LOG_LOCAL0
#	- Facilities
#		- LOG_AUDIT - audit daemon (IRIX); falls back to LOG_AUTH
#		- LOG_AUTH - security/authorization messages
#		- LOG_AUTHPRIV - security/authorization messages (private)
#		- LOG_CONSOLE - /dev/console output (FreeBSD); falls back to LOG_USER
#		- LOG_CRON - clock daemons (cron and at)
#		- LOG_DAEMON - system daemons without separate facility value
#		- LOG_FTP - FTP daemon
#		- LOG_KERN - kernel messages
#		- LOG_INSTALL - installer subsystem (Mac OS X); falls back to LOG_USER
#		- LOG_LAUNCHD - launchd - general bootstrap daemon (Mac OS X); falls back to LOG_DAEMON
#		- LOG_LFMT - logalert facility; falls back to LOG_USER
#		- LOG_LOCAL0 through LOG_LOCAL7 - reserved for local use
#		- LOG_LPR - line printer subsystem
#		- LOG_MAIL - mail subsystem
#		- LOG_NETINFO - NetInfo subsystem (Mac OS X); falls back to LOG_DAEMON
#		- LOG_NEWS - USENET news subsystem
#		- LOG_NTP - NTP subsystem (FreeBSD, NetBSD); falls back to LOG_DAEMON
#		- LOG_RAS - Remote Access Service (VPN / PPP) (Mac OS X); falls back to LOG_AUTH
#		- LOG_REMOTEAUTH - remote authentication/authorization (Mac OS X); falls back to LOG_AUTH
#		- LOG_SECURITY - security subsystems (firewalling, etc.) (FreeBSD); falls back to LOG_AUTH
#		- LOG_SYSLOG - messages generated internally by syslogd
#		- LOG_USER (default) - generic user-level messages
#		- LOG_UUCP - UUCP subsystem
# @param String $setlogsockType
#	- механизмы передачи в сислог. По умолчанию unix
#		- "native" - use the native C functions from your syslog(3) library (added in Sys::Syslog 0.15).
#		- "eventlog" - send messages to the Win32 events logger (Win32 only; added in Sys::Syslog 0.19).
#		- "tcp" - connect to a TCP socket, on the syslog/tcp or syslogng/tcp service. See also the host , port and timeout options.
#		- "udp" - connect to a UDP socket, on the syslog/udp service. See also the host , port and timeout options.
#		- "inet" - connect to an INET socket, either TCP or UDP, tried in that order. See also the host , port and timeout options.
#		- "unix" - connect to a UNIX domain socket (in some systems a character special device). The name of that socket is given by the path option or, if omitted, the value returned by the _PATH_LOG macro (if your system defines it), /dev/log or /dev/conslog, whichever is writable.
#		- "stream" - connect to the stream indicated by the path option, or, if omitted, the value returned by the _PATH_LOG macro (if your system defines it), /dev/log or /dev/conslog, whichever is writable. For example Solaris and IRIX system may prefer "stream" instead of "unix" .
#		- "pipe" - connect to the named pipe indicated by the path option, or, if omitted, to the value returned by the _PATH_LOG macro (if your system defines it), or /dev/log (added in Sys::Syslog 0.21). HP-UX is a system which uses such a named pipe.
#		- "console" - send messages directly to the console, as for the "cons" option of openlog() .
# @return
#	void
#	создает вывод в сислог
sub openLog {
	my ($logname,$facility,$setlogsockType) = @_;
	if (!defined $logname) {$logname = 'TEST-APP';}
	if (!defined $facility) {$facility = 'LOG_LOCAL0';}
	if (!defined $setlogsockType) {$setlogsockType = 'unix';}
	Sys::Syslog::setlogsock($setlogsockType);
	openlog($logname,'ndelay,pid', $facility);
}

# Записывает в системный лог
# @param String $message
#	- текст сообщения, которое необходимо вывести в системный лог
# @param boolean $toTranslit
#	- Вывод в системный лог в транслитированном виде. Полезно использовать в таких системах, как freeBSD
# @param String $logLevel
#	- Уровень вывода в сислог (ядро сислога)
#	- info|notice|debug|mail|warring
# @param String $messgaeLevel
#	- Уровень вывода в сислог (клеится к тексту каждого сообщения)
#	- alert|notice	- простое сообщение
#	- warring 		- предупреждение
#	- error			- ошибка
# @return
#	void
#	пишет в системный лог
sub toSyslog {
	my ($message,$toTranslit,$logLevel,$messageLevel) = @_;
	if ((!defined $logLevel)||($logLevel eq '')) {$logLevel = 'alert';}
	if ((!defined $messageLevel)||($messageLevel eq '')) {$messageLevel = 'alert';}
	if ((!defined $message)||($message eq '')) {$message = 'UNDEF';}
	unless(utf8::is_utf8($message)) {
		$message = decode("utf8",$message);
	}
	$messageLevel = lc($messageLevel);
	if ((defined $toTranslit)&&($toTranslit)) {
		$message = text::stringToTranslit($message);
	}
	syslog($logLevel, $messageLevel.": ".$message);
}

# Закрывает системный лог
# @return
#	void
sub closeLog {
	closelog();
}
1;