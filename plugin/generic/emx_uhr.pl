# Plugin zum Zeitabhaengigen Schalten von GA's (Schaltuhr)
# License: GPL (v2)
# version von emax
#
# $Id$
#
# Copyright: Edgar (emax) Hermanns, forum at hermanns punkt net
#--------------------------------------------------------------------
#  CHANGE LOG:
#  ##  who  yyyymmdd   bug#  description
#  --  ---  --------  -----  ----------------------------------------
#   .  ...  ........  .....  vorlage 
#   6  edh  20120706  .....  Zeitzonen eingefuehrt. Durch Angabe 
#                             des neuen Parameters 'Zone' in der 
#                             @Zeiten Tabelle kann nun festgelegt
#                             werden, fuer welche Zeitzone der 
#                             Schaltzeitpunkt berechnet werden soll.
#                             Der Parameter is wahlweise, so dass
#                             bisherige conf-Dateien ohne Aenderung
#                             weiter verwendet werden koennen.
#                             Eine detaillierte Dokumentation findet
#                             sich in der conf-Datei, die auch Beipiele
#                             enthaelt.
#   5  edh  20111023  .....  conf.d Verzeichnis eingefuehrt. Alle 
#                             Einstellungen werden kuenftig ueber
#                             ueber eine entsprechende Konfigura-
#                             tionsdatei conf.d/plugin.conf vorge-
#                             nommen, Einzelheiten siehe dort.
#   4  edh  20111010  .....  - Null-Werte wurden falsch verarbeitet
#                            - Zyklusberechnung konnte wg. Rundung 
#                              in underruns (Minuten-Unterschreitung) 
#                              resultieren, wird jetzt durch Addition 
#                              eines Zusatzwertes vermieden. 
#                              Allerdings sind tw. immer noch solche 
#                              Underruns zu beobachten, die anscheinend
#                              wg. unkorrektem timings von 'aussen' 
#                              verursacht werden. Das Script faengt 
#                              diese underruns allerdings ebenfalls ab.                              
#   3  edh  20110910  .....  Zykluszeit wurde nicht korrekt verarbeitet,
#                            Zyklus-Anpassung nun exakt in Sekunden,
#                            -  dadurch keine 1-Sekunden leer-Zyklen mehr,
#                            -  weniger Systemlast.
#                            Alte plugin_info Eintraege werden bei neuer 
#                             versionsnummer nun bereinigt.
#   2  edh  20110910  -----  Bug im Wertevergleich in 'matches()' gefixt
#   1  edh  20110807  -----  wg. utf-8 Zirkus Umlaute in ae/ue/oe geaendert
#   0  edh  20110708  -----  erste Version

use POSIX;
use Time::Zone;

#-----------------------------------------------------------------------------
# konfigurierbare  Werte, siehe conf.d/emx_uhr.conf.sample
#-----------------------------------------------------------------------------
my @Zeiten               = ();
my $LokaleZeitZone       = "CET";  # lokale Zeitzone
my $LokaleSommerZeitZone = "CEST"; # lokale Zeitzone im Sommer
my $slotEnd = 3; 

#-----------------------------------------------------------------------------
# Aufruf-Zyklus setzen
# Das script verarbeitet keine Sekunden, weshalb die kleinste 
# Granularitaet ohne zusaetzliche Statusverarbeitung eine Minute ist. 
#-----------------------------------------------------------------------------
my $cycleTime = 60;

#-----------------------------------------------------------------------------
# Die Versionsnummer is Teil des plugin_info hashes und dient
# dazu, dass das script definierte Anfangskonditionen findet 
# auch ohne den wiregated neu starten zu muessen. Die Nummer 
# einfach nach einer Aenderung des scripts um eins erhoehen.
#-----------------------------------------------------------------------------
my $version = 11;

#-----------------------------------------------------------------------------
# Numerischen String als Zahl zurueckgeben
# - blanks entfernen
# - fuehrende Nullen entfernen
#-----------------------------------------------------------------------------
sub toNumber
{
    my $value = shift;
    (!defined $value) and return 0;

    $value =~ s/\s+//g; # whitespace entfernen
    $value =~ s/^0+(.)$/$1/g; # fuehrende Nullen entfernen
    return $value;
} # toNumber

#-----------------------------------------------------------------------------
# Auswertung von Bereichs und Listenvergleichen
# Prueft, ob ein Wert zu einer Liste oder in einen Bereich passt
#-----------------------------------------------------------------------------
sub matches
{
    my ($value, $def) = @_;  # Zu pruefender Wert, Bereichsdefinition
    (!defined $def)  and return 1;
    $value = &toNumber($value);

    foreach (split(/,/, $def))
    {
        $_ = &toNumber($_);
	# Vergleich auf Alpha-Basis (vermeidet Laufzeit-Fehler)
        (/^$value$/) and return 1;
        (/^([\d]+)-(\d+)/) and return ($value >= $1 && $value <= $2);
    }
    return 0;
} # matches

#-----------------------------------------------------------------------------
# Zykluszeit berechnen und neu setzen
#-----------------------------------------------------------------------------
sub setCycle
{
    my ($seconds,$uSec) = gettimeofday();
    my $curSec = $seconds%60;
    if ($curSec >= $slotEnd)
    {
	$plugin_info{$plugname.'_cycle'} = $cycleTime - $curSec - $uSec/1000000 + 0.1; # avoid rounding underruns
	plugin_log($plugname, "cycle time set to $plugin_info{$plugname.'_cycle'} second");
    }
    else
    {
	$plugin_info{$plugname.'_cycle'} = $cycleTime;
    }
}

#-----------------------------------------------------------------------------
# Konfiguration lesen. Erwartet wird eine Datei conf.d/emx_uhr.conf
#-----------------------------------------------------------------------------
sub readConf
{
    my $confFile = '/etc/wiregate/plugin/generic/conf.d/'.basename($plugname,'.pl').'.conf';
    if (! -f $confFile)
    {
        plugin_log($plugname, "no conf file [$confFile] found."); 
    }
    else
    {
        plugin_log($plugname, "reading conf file [$confFile]."); 
        open(CONF, $confFile);
        my @lines = <CONF>;
        close($confFile);
        my $result = eval("@lines");
        ($result) and plugin_log($plugname, "conf file [$confFile] returned result[$result]");
        if ($@) 
        {
            plugin_log($plugname, "ERR: conf file [$confFile] returned:");
            my @parts = split(/\n/, $@);
            plugin_log($plugname, "--> $_") foreach (@parts);
        }
    }
} # readConf

#=============================================================================
# main()
#=============================================================================

my $tStamp = time;
my ($curSec,$curMin,$curStu,$curMTag,$curMon,$curJahr,$curWTag,$curJTag,$isdst) = localtime($tStamp);
$curJahr += 1900;

# set the time zone to use here and now
my $curZone = ($isdst) ? $LokaleSommerZeitZone : $LokaleZeitZone;
my $lclOffset = tz_offset("$curZone");

&readConf();

# kontrollierte Startkonditionen setzen
if (!defined $plugin_info{"$plugname.$version.firstRun"})
{
    plugin_log($plugname, "Starting plugin version $version, will execute with first time-slot.");
    # obsolete Versionen von $plugin_info bereinigen
    foreach (keys %plugin_info)
    {
	if (/^$plugname\./)
	{
	    delete $plugin_info{$_};
	    plugin_log($plugname, "deleted plugin_info[$_]");
	}
    }    
    $plugin_info{"$plugname.$version.firstRun"} = 1;
    &setCycle();
}

# beim ersten Mal nur ausfuehren, wenn innerhalb des slots
($curSec >= $slotEnd && $plugin_info{"$plugname.$version.firstRun"} == 1) and return;

# pruefen, ob in dieser Minute bereits ausgefuehrt
if (defined $plugin_info{"$plugname.$version.lastMinute"} && $plugin_info{"$plugname.$version.lastMinute"} == $curMin)
{
    &setCycle();
    return;
}

# create the 'basetime' which is used for calclulations
my ($basSec,$basMin,$basStu,$basMTag,$basMon,$basJahr,$basWTag,$basJTag) =
    ($curSec,$curMin,$curStu,$curMTag,$curMon,$curJahr,$curWTag,$curJTag);

foreach my $Zeit (@Zeiten) 
{
    (defined $Zeit->{Aktiv} && !$Zeit->{Aktiv})                    and next;
    my $baseZone = (defined $Zeit->{Zone} && (length($Zeit->{Zone}) >= 3) ) ? $Zeit->{Zone} : $curZone;
    if ($baseZone ne $curZone)         # different time zone than local,recalculate time values for defined zone
    {
        ($basSec,$basMin,$basStu,$basMTag,$basMon,$basJahr,$basWTag,$basJTag) = localtime($tStamp-$lclOffset+tz_offset($baseZone));
        $basJahr += 1900;
    }

    (defined $Zeit->{Min}   && !&matches($basMin,  $Zeit->{Min}))  and next;
    (defined $Zeit->{Std}   && !&matches($basStu,  $Zeit->{Std}))  and next;
    (defined $Zeit->{MTag}  && !&matches($basMTag, $Zeit->{MTag})) and next;
    (defined $Zeit->{Mon}   && !&matches($basMon,  $Zeit->{Mon}))  and next;
    (defined $Zeit->{WTag}  && !&matches($basWTag, $Zeit->{WTag})) and next;
    (defined $Zeit->{Log}   && $Zeit->{Log} eq '1') and 
        plugin_log($plugname, sprintf "Sending at[$baseZone %02d:%02d:%02d],Value[$Zeit->{Wert}],GA[$Zeit->{GA}]",
                   $basStu,$basMin,$basSec);

    (defined ($Zeit->{GA}) && knx_write($Zeit->{GA},$Zeit->{Wert}, $Zeit->{DPT}));
} # foreach (@Zeiten)

$plugin_info{"$plugname.$version.lastMinute"} = $curMin;

# ggf. Zykluszeit korrigieren
&setCycle();
$plugin_info{"$plugname.$version.firstRun"} = 0;
