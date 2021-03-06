﻿# Plugin zum Senden eines Befehles auf eine GA abhaengig von der aktiven Weckzeit aus dem Chumby.
#
# basiert auf chumby_weckzeit.pl von swiss (http://knx-user-forum.de/members/swiss.html)
#
# Version 0.2 BETA 17.02.1013
# Copyright: jensgulow (http://knx-user-forum.de/members/jensgulow.html)
# License: GPL (v2)
# Aufbau moeglichst so, dass man unterhalb der Einstellungen nichts veraendern muss!
#
#
####################
###Einstellungen:###
####################

my $chumby_ip 	= "xxx.xxx.xxx.xxx"; 					# Hier die IP-Adresse des Chumby eintragen.

my $trigger_ga 	= "12/0/0";								# Auf diese GA wird zum aktiven Weckzeitpunkt eine $value_trigger_ga gesandt.

my $value_trigger_ga = "1";								# Dieser Wert wird an $trigger_ga gesandt.

my $DPT_trigger_ga = "1.001";							# DPT des gesendeten Wertes.

######################
##ENDE Einstellungen##
######################

# Eigenen Aufruf-Zyklus auf xx sek. setzen
$plugin_info{$plugname.'_cycle'} = 55; 


use POSIX;
use XML::Simple;
use LWP::Simple;
use Encode qw(encode decode);
use Time::Local;
# use open ":utf8";

my $sec; 		#Sekunde
my $min; 		#Minute
my $hour; 		#Stunde
my $mday; 		#Monatstag
my $mon; 		#Monatsnummer
my $year; 		#Jahr
my $wday; 		#Wochentag 0-6
my $yday; 		#Tag ab 01.01.des aktuellen Jahres
my $isdst;

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		 
my $perltime = int(60*$hour+$min);			# rechnet auf die im Chumby verwendete Darstellung für time='' um
											# z.B. 5:30 Uhr = 330
											
my $perltimemin = int(time/60);				# Minuten seit dem 01.01.1970 (wird bei einmaligen Weckterminen als time='' verwandt
											
my $command = "ping -c 2 -w 2 ".$chumby_ip;
my $status = `$command`;
if($status =~ /bytes from/)
{
	my $url = "http://$chumby_ip/cgi-bin/custom/alarms.pl?page=download";
	my $xml = encode("utf8",get($url));
	die "Fehler beim Aufrufen der URL: $url. Bitte mit Anleitung ueberpruefen." unless defined $xml;
	my $alarms = XMLin($xml)->{alarm};		# Die alarms-Datei parsen
	
SCHALTZEITPUNKT: while ((my $key) = each %{$alarms})
{
		### Fall "daily" als eingetragene Wecktage ###
		if ($alarms->{$key}->{enabled} == 1 && $alarms->{$key}->{time} == $perltime && $alarms->{$key}->{when} eq 'daily' && $alarms->{$key}->{auto_dismiss} == '0')
						{
						knx_write($trigger_ga,$value_trigger_ga,$DPT_trigger_ga);
				        plugin_log($plugname, "geschalten, da Weckzeitpunkt erreicht. Sende [$value_trigger_ga] an $trigger_ga.");
						last SCHALTZEITPUNKT;
						}

		### Fall "Once on xx/xx/xxxx" als eingetragener einmaliger Wecktag ###
		elsif ($alarms->{$key}->{enabled} == 1 && $alarms->{$key}->{time} == $perltimemin && $alarms->{$key}->{when} eq 'once' && $alarms->{$key}->{auto_dismiss} == '0')
						{
						knx_write($trigger_ga,$value_trigger_ga,$DPT_trigger_ga);
						plugin_log($plugname, "geschalten, da Weckzeitpunkt erreicht. Sende [$value_trigger_ga] an $trigger_ga.");
						last SCHALTZEITPUNKT;
						}
					
		### Fall "dowxxxxxxx" als eingetragene Wecktage (individuelle Einstellung "day of week" ###
		elsif ($alarms->{$key}->{enabled} == 1 && $alarms->{$key}->{time} == $perltime && $alarms->{$key}->{auto_dismiss} == '0')
				{
				if ($alarms->{$key}->{when} =~ /dow(\d{7})/)
					{
						my $wdaybinaer = $1;
						my @zeichen;
						for(my $j=0; $j<7; $j++) 
							{
							$zeichen[$j] = substr($wdaybinaer,$j,1);
							if ($zeichen[$j] == 1 && $j eq $wday)
								{
								knx_write($trigger_ga,$value_trigger_ga,$DPT_trigger_ga);
								plugin_log($plugname, "geschalten, da Weckzeitpunkt erreicht. Sende [$value_trigger_ga] an $trigger_ga.");
								last SCHALTZEITPUNKT;
								}
							}
					}
				}
			next;
}

	return "Status OK";
			
}

elsif($status =~ /0 received/) 
{
	return "Ein Fehler ist beim Testen der IP $chumby_ip aufgetreten";
}