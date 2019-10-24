
##############################################
# $Id: 98_MediaList.pm 20005 2019-08-16 09:46:20Z Tobias.Faust $
#
# 98_MediaList.pm
#
# written by Tobias Faust 2016-12-19
# contributions by Prof. Dr. Peter A. Henning 2019
# e-mail: tobias dot faust at gmx dot net
#
##############################################  
#
##############################################
#
#   Log-Levels
#    0 - server start/stop
#    1 - error messages or unknown packets
#    2 - major events/alarms.
#    3 - commands sent out will be logged.
#    4 - you'll see whats received by the different devices.
#    5 - debugging.
#
##############################################
#
##############################################
## install package libmp3-tag-perl, libjson-xs-perl, libmp3-info-perl
##
## images/cd-empty.png
##############################################


use strict;
use warnings;
use Data::Dumper;
use POSIX;
use utf8;
no utf8;
use Encode;
use MP3::Tag;
use MP3::Info;
use JSON::XS;
#use open IN => ":encoding(utf8)", OUT => ":utf8";
use IO::File;
use Fcntl;
use File::Basename;
use File::Copy;
require 'Blocking.pm';
require 'HttpUtils.pm';
use vars qw($readingFnAttributes);

# use vars qw(%attr);
use vars qw(%defs);

my %sets;

###########################################################################

sub MediaList_Initialize($)
{
   my ($hash) = @_;
   $hash->{DefFn}    = "MediaList_Define";
#   $hash->{UndefFn}  = "MediaList_Undef";
   $hash->{SetFn}    = "MediaList_Set";
#   $hash->{DeleteFn} = "MediaList_Delete";
   $hash->{AttrList} = " MediaList_PlayerDevice". 
                       " MediaList_PlayerType:SONOS,BOSE,MPD". # PAH
                       " MediaList_PathReplaceFrom". 
                       " MediaList_PathReplaceTo".
                       " MediaList_PathReplaceToPic".
                       " MediaList_PlayerStartCommand".
                       " MediaList_PlayerImmediateCommand".
                       " MediaList_CacheFileDir". # TODO: $hash->{.PLAYLISTPATH} muss bei Änderung des CacheFileDir angepasst werden
                       " MediaList_mkTempCopy:none,copy,symlink".
#                       " MediaList_allowedExtensions".
                       " ".$readingFnAttributes;

  # SetParamName -> Anzahl Paramter
  %sets = (
    "RequestedDirectory"    => { "count" => "1" },
    "Play"                  => { "count" => "2", "args" => "currentdir,playlist" },
    "Playlist_New"          => { "count" => "1"}, #Arg: PlaylistName, optional
    "Playlist_Name"         => { "count" => "1"}, #Arg: Name der Playlist
    "Playlist_Add"          => { "count" => "2"}, #Medien aus CurrentDir werden hinzugefügt oder sofort abgespielt 
    "Playlist_Del"          => { "count" => "1"}, #Arg: TrackNr
    "Playlist_Empty"        => { "count" => "0", "args" => "noArg"}, #Leeren
    "Playlist_Save"         => { "count" => "0", "args" => "noArg"}, #Sichern ohne abzuspielen
    "Playlist_Read"         => { "count" => "0", "args" => "noArg"}, #Sichern ohne abzuspielen
#    "Playlist_Drop"         => { "count" => "1"}  #Loeschen, erst relevant wenn abgespeicherte Playlist 
    "SortBy"                => { "count" => "1", "args" => "File,Title"}
  );

}
###########################################################################

sub MediaList_Define($$)
{
  my ( $hash, $def ) = @_;
  my $me   = $hash->{NAME};
  my @a    = split( "[ \t][ \t]*", $def );
  my $type = $a[1];
  
  return "Wrong syntax: use define <name> MediaList <RootFolder>" if ( int(@a) != 3 );
  
  my $MediaList_CacheFileDir = AttrVal($me, "MediaList_CacheFileDir", "cache/");

  $hash->{ROOT} = $a[2];
  #$hash->{".PLAYLISTPATH"} = $MediaList_CacheFileDir."/playlists_$me";

  unless(-e $MediaList_CacheFileDir or mkdir $MediaList_CacheFileDir) {
    #Verzeichnis anlegen gescheitert
    Log3 $hash->{NAME}, 2, "MediaList: Angegebenes Verzeichnis $MediaList_CacheFileDir konnte erstmalig nicht angelegt werden.";
    return undef;
  }

  #unless(-e $hash->{".PLAYLISTPATH"} or mkdir $hash->{".PLAYLISTPATH"}) {
    #Verzeichnis anlegen gescheitert
  #  Log3 $hash->{NAME}, 2, "MediaList: Angegebenes Verzeichnis $hash->{.PLAYLISTPATH} konnte erstmalig nicht angelegt werden.";
  #  return undef;
  #}


   return undef;
}

###########################################################################

sub MediaList_Undef($$)
{
   my ( $hash, $arg ) = @_;

   BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined( $hash->{helper}{RUNNING_PID} ) );
   
   return undef;
}


###########################################################################

sub MediaList_Delete($$)
{
   my ( $hash, $arg ) = @_;
   # TODO: alle Files manuell vorher löschen

   #if (-e $hash->{".PLAYLISTPATH"}) {
   # Log3 $hash->{NAME}, 1, "Cannot delete ".$hash->{".PLAYLISTPATH"}.". Please clean up by yourself." unless rmdir $hash->{".PLAYLISTPATH"}); 
   #}

   return undef;
}

###########################################################################

sub MediaList_Set($@)
{
  my ($hash, @a) = @_;
  my $me = $hash->{NAME};
 
  return "no set argument specified" if(int(@a) < 2);

  my $cmd = shift(@a); # Device
     $cmd = shift(@a); # Command
  my $par = join(" ", @a); # parameter   

  if(!defined($sets{$cmd})) {
    my @s;
    foreach my $key (sort keys(%sets)) {
      $key = $key .":" . $sets{$key}{"args"} if ($sets{$key}{"args"}); 
      push(@s, $key);
    }

    my $r = "Unknown argument $cmd, choose one of ".join(" ",@s);
    return $r;
  }

  if($cmd eq "RequestedDirectory") {
    return "$cmd needs ".$sets{$cmd}{"count"}." parameter(s)" if(@a-$sets{$cmd}{"count"} < 0);

    MediaList_Crawl($hash, $par);
    MediaList_call_playlistinfo($hash, ReadingsVal($me, "CurrentDir", $hash->{ROOT}));
  }

  if($cmd eq "Playlist_New") {
    $par="MyNewPlaylist" if($par eq "");
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "playlistname", $par);
    readingsBulkUpdate($hash, "playlist", "[]");
    readingsBulkUpdate($hash, "playlistduration", "");    
    readingsEndUpdate($hash, 1);
  }

  if($cmd eq "Playlist_Empty") {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "playlist", "[]");
    readingsBulkUpdate($hash, "playlistduration", "");
    readingsEndUpdate($hash, 1);
  }

  if($cmd eq "Playlist_Add") {
    Log 1," ===========> par=$par";
    #-- first case: no parameter at all or a single numerical parameter 
    #               or a single numerical parameter and "a"
    if( ($par eq "") || ($par =~ m/[0-9]+(.*a)?$/) ){
      $par =~ s/a//;
      MediaList_PlayListAdd($hash, $par);
    #--second case: single numerical parameter and "i"  
    }elsif( $par =~ m/[0-9]+.*i$/ ){
      $par =~ s/i//;
      MediaList_PlayImmediate($hash, $par);
    }else{
      return "given parameter not an integer value";
    }
  }

  if($cmd eq "Playlist_Name") {
    return "no name specified" if($par eq "");
    readingsSingleUpdate($hash, "playlistname", $par, 1);
  }  
 
  if($cmd eq "Playlist_Del") {
    return "no track number specified" if($par !~ m/[0-9]+/);
    MediaList_PlayListDel($hash, $par);
  }

  if($cmd eq "Playlist_Drop") {
    # gespeicherte Playlist auf HDD löschen
  }

 if($cmd eq "Playlist_Save") {
   my $dir = shift(@a);
   MediaList_Create($hash, $dir, "");
  }

  if($cmd eq "Play") {
    my $dir = shift(@a);
    #-- check for device parameter
    my $dev = shift(@a);
    my $adev = AttrVal($me, "MediaList_PlayerDevice", undef);
    
    my $pldev;
    my $PlayerStartCommand  = AttrVal($me, "MediaList_PlayerStartCommand", undef);
    
    #-- first case: no parameter at all. Device from attribute, play CurrentDir
    if( !$dir && !$dev ){
      $pldev = $adev;
      $dir   = "currentdir";
    #-- second case: parameter is currentdir|playlist. Device from next parameter or attribute
    }elsif( $dir =~ /(currentdir)|(playlist)/ ){
      $pldev = ($dev)?$dev:$adev;
    #-- last case: Device from second parameter or attribute
    }else{
      $pldev = ($dev)?$dev:$adev;
      $dir = "currentdir";
    }
    return "Argument not known, keep empty for currentdir or playlist for your managed playlist" if $dir !~ m/(currentdir|playlist)/;
    MediaList_Create($hash, $dir, $pldev);
  }

  # sortiere Playlist nach Kriterien, zb. File, Title, Artist, etc
  if($cmd eq "SortBy") {
    return "sort criteria required: ". $sets{$cmd}{"args"} if (!$par);

    my $json = ReadingsVal($me, "currentdir_playlist", "[]");
    return "no currentdir_playlist available, please select one" if($json eq "[]");

    $json = MediaList_playlist_sort($json, $par, "asc"); 
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "currentdir_playlist",  $json);
    readingsBulkUpdate($hash, "sortby",  $par);
    readingsEndUpdate($hash, 1);

    return undef;
  }
}

###########################################################################
###########################################################################
###########################################################################

####################################
# 
####################################
sub MediaList_Create ($$$) {
  my ($hash, $pltype, $pldev) = @_;
  my $me = $hash->{NAME};

  my $PlayerType            = AttrVal($me, "MediaList_PlayerType", undef);
  my $PathReplaceFrom    	= AttrVal($me, "MediaList_PathReplaceFrom", undef);
  my $PathReplaceTo      	= AttrVal($me, "MediaList_PathReplaceTo", "");
  my $PlayerStartCommand  	= AttrVal($me, "MediaList_PlayerStartCommand", undef);
  my $MediaList_CacheFileDir= AttrVal($me, "MediaList_CacheFileDir", "cache/");
  my $MediaList_mkTempCopy	= AttrVal($me, "MediaList_mkTempCopy", "none");
  my $playlist;
  my $playlistduration;
  
  if ($pltype eq "currentdir") {
    $playlist = ReadingsVal($me, "currentdir_playlist", "");
    $playlistduration = ReadingsVal($me, "currentdir_playlistduration", "");
  } else {
    $playlist = ReadingsVal($me, "playlist", "");
    $playlistduration = ReadingsVal($me, "playlistduration", "");
  }

  return "Playlist empty" unless($playlist);

  my $plname = ReadingsVal($me,"playlistname",$pldev); 
  my $plfile   = $MediaList_CacheFileDir.$plname.".m3u";
  
  Log 1,"=============> file $plfile";
  
  #-- delete previous file
  if( $PlayerType eq "BOSE" ){
    unlink($PathReplaceFrom.$plname.".m3u");
    Log 1, " ===> ".$PathReplaceFrom.$plname.".m3u deleted";
  }
  
  my @data = @{JSON::XS->new->decode($playlist)};

  my $fh;
  my $hash_target = $defs{$pldev};
  
  # check, if fhem system hardware supports symlinks
  my $symlink_check = eval{symlink("","");1};
  $MediaList_mkTempCopy = "copy" if($MediaList_mkTempCopy eq "symlink" && $symlink_check != 1);

  # delete all outdated symbolic links (VORSICHT! KANN ZUM DATENVERLUST FÜHREN)
  if ($symlink_check == 1) {
    opendir(my $dh, $MediaList_CacheFileDir) || die "Medialist: $MediaList_CacheFileDir: $!";
    while(my $filename = readdir($dh)) {
      if( -l $MediaList_CacheFileDir.$filename && $filename =~ m/^$me/) {
        unlink($MediaList_CacheFileDir.$filename);
      }
    }
    closedir($dh); # nicht vergessen
  }

  $fh = new IO::File ">$plfile";
  
  if( $fh ){
    for(my $j=0; $j<=$#data; $j++) {
  
      my $utf8file = decode("UTF-8","$data[$j]->{File}");
      my $newName = $MediaList_CacheFileDir.$me."_".basename($utf8file);
      my $ret;

      $newName =~ s/ä/ae/g;
      $newName =~ s/ö/oe/g;
      $newName =~ s/ü/ue/g;
      $newName =~ s/Ä/Ae/g;
      $newName =~ s/Ö/Oe/g;
      $newName =~ s/Ü/Ue/g;
      $newName =~ s/ß/ss/g;

      if ($MediaList_mkTempCopy eq "symlink") {
        $ret = symlink($utf8file, $newName);
        $data[$j]->{File} =  basename($newName);
      } elsif ($MediaList_mkTempCopy eq "copy") {
        $ret = copy($utf8file, $newName);	  
        $data[$j]->{File} =  basename($newName);
      } else {
        $data[$j]->{File} = $utf8file;
      }

      #-- PathReplaceTomay be missing, in this case only delete PathReplaceFrom
      if ($PathReplaceFrom && $PathReplaceTo){ 
        $data[$j]->{File} =~ s/^($PathReplaceFrom)/$PathReplaceTo/ ;
      }elsif ($PathReplaceFrom){
        $data[$j]->{File} =~ s/^($PathReplaceFrom)// ;
      }
      $fh->print("". encode("UTF-8", $data[$j]->{File}) ."\n");
      Log3 $hash->{NAME}, 5, "MediaList: File prepared for player $pldev: ".$data[$j]->{File};
    }
    close($fh);
  }else{
    Log3  $hash->{NAME}, 1, "MediaList: Error, file $plfile could not be opened";
  }

  #-- copy directly to device only if SONOS or MPD
  if( $PlayerType ne "BOSE" ){
    readingsBeginUpdate($hash_target);
    readingsBulkUpdate($hash_target, "playlist_json", $playlist);
    readingsBulkUpdate($hash_target, "playlistduration", $playlistduration);
    readingsEndUpdate($hash_target, 1);
  }
  #-- copy to target directory
  my $ret=copy($plfile,$PathReplaceFrom);
  
  #-- start playing at the specified device
  if ($PlayerStartCommand && ($pldev ne "") ) {
    return "Player device not available: ".$pldev unless ($defs{$pldev});
   
    my($cmd_file, $cmd_dir, $cmd_ext) = fileparse($plfile, qr"\..[^.]*$");
  
    $PlayerStartCommand =~ s/\<fullfile\>/$plfile/;
    $PlayerStartCommand =~ s/\<filename\>/$cmd_file/;
    $PlayerStartCommand =~ s/\<fileext\>/$cmd_ext/;
    $PlayerStartCommand =~ s/\<device\>/$pldev/;
    Log3  $hash->{NAME}, 1, "MediaList: Start player with: set ".$pldev." ".$PlayerStartCommand;
    fhem ("set ".$pldev." ".$PlayerStartCommand);
  }

  return undef; 
}

##################################
# PlayImmediate
# Parameter: Tracknummer
##################################
sub MediaList_PlayImmediate($$) {
  my ($hash, $par) = @_;
  my $me = $hash->{NAME};

  my $curpl    = ReadingsVal($me, "currentdir_playlist", "");
  #my $curpldur = ReadingsVal($me, "currentdir_playlistduration", 0);
  #my $pl       = ReadingsVal($me, "playlist", "");
  #my $pldur    = ReadingsVal($me, "playlistduration", 0);
  my $PathReplaceFrom    	= AttrVal($me, "MediaList_PathReplaceFrom", undef);
  my $PathReplaceTo      	= AttrVal($me, "MediaList_PathReplaceTo", "");
  my $PlayerStartCommand  	= AttrVal($me, "MediaList_PlayerStartCommand", undef);
  return "Playlist empty" unless($curpl);

  my @curpldata;
  my @pldata;
  @curpldata    = @{JSON::XS->new->decode($curpl)};

  return "Invalid track number, only ". $#curpldata ." tracks available" if($par>(scalar @curpldata));
  
  push(@pldata, $curpldata[$par]);
 
  my $utf8file = decode("UTF-8","$curpldata[$par]->{File}");

  #-- PathReplaceTomay be missing, in this case only delete PathReplaceFrom
  if ($PathReplaceFrom && $PathReplaceTo){ 
    $utf8file =~ s/^($PathReplaceFrom)/$PathReplaceTo/ ;
  }elsif ($PathReplaceFrom){
    $utf8file =~ s/^($PathReplaceFrom)// ;
  }
  Log3 $hash->{NAME}, 1, "MediaList: File prepared for player ".$utf8file;

}

###################################
# PlaylistFunktionen
##################################
# PlaylistAdd
# Parameter: Tracknummer oder leer (Alle Tracks werden verwendet)
##################################
sub MediaList_PlayListAdd($$) {
  my ($hash, $par) = @_;
  my $me = $hash->{NAME};

  my $curpl    = ReadingsVal($me, "currentdir_playlist", "");
  my $curpldur = ReadingsVal($me, "currentdir_playlistduration", 0);
  my $pl       = ReadingsVal($me, "playlist", "");
  my $pldur    = ReadingsVal($me, "playlistduration", 0);

  return "Playlist empty" unless($curpl);

  my @curpldata;
  my @pldata;
  @curpldata    = @{JSON::XS->new->decode($curpl)};
  @pldata       = @{JSON::XS->new->decode($pl)}     if($pl ne "");    # CRASH HERE

  if($par eq "") {
    # alles übergeben
    push(@pldata, @curpldata);
    $pldur += $curpldur;
  } else {
    return "Argument not an integer" if($par !~ m/[0-9]+/);
    return "Invalid track number, only ". $#curpldata ." tracks available" if($par>(scalar @curpldata));
    push(@pldata, $curpldata[$par]);
    $pldur += $curpldata[$par]->{Time};
  }

  $pl = JSON::XS->new->encode(\@pldata);

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "playlist", $pl);
  readingsBulkUpdate($hash, "playlistduration", $pldur);
  readingsEndUpdate($hash, 1);

}

##################################
# PlaylistDel
# Parameter: Tracknummer die aus der PL geloescht werden soll
##################################
sub MediaList_PlayListDel($$) {
  my ($hash, $par) = @_;

  my $me = $hash->{NAME};

  my $pl = ReadingsVal($me, "playlist", "");
  my $pldur = ReadingsVal($me, "playlistduration", 0);

  return "Playlist empty" unless($pl);
  return "Argument not an integer" if($par !~ m/[0-9]+/);

  my @pldata;
  @pldata    = @{JSON::XS->new->decode($pl)};

  return "Invalid track number, only ". $#pldata ." tracks available" if($par>(scalar @pldata));
  
  $pldur -= $pldata[$par]->{Time};
  splice(@pldata, $par, 1);

  $pl = JSON::XS->new->encode(\@pldata);

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "playlist", $pl);
  readingsBulkUpdate($hash, "playlistduration", $pldur);
  readingsEndUpdate($hash, 1);

}

####################################
# Startfunktion zur PlaylistInfo
####################################
sub MediaList_call_playlistinfo($$) {
  my ($hash, $object) = @_; 
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "status",  "gathering filelist");
  readingsEndUpdate($hash, 1);

  #Log 3 , "$device: MediaList_call_playlistinfo";
  $hash->{helper}{RUNNING_PID} = BlockingCall("MediaList_CollectID3Tags", $hash->{NAME}."|".$object, "MediaList_done_playlistinfo", 120); #, "MediaList_AbortFn", $hash
  return undef;
}

####################################
# Abschlussfunktion zur PlaylistInfo
####################################
sub MediaList_done_playlistinfo($) {
  my ($string) = @_;
  my @t = split(/\|/, $string);
  my $hash=$defs{$t[0]};
  my $playlist= $t[1];
  my $playlistduration = 0;

  delete($hash->{helper}{RUNNING_PID});

  $playlist = MediaList_playlist_sort($playlist, "File", "asc"); # sortiere Playlist per default nach Dateinamen

  my @data = @{JSON::XS->new->decode($playlist)}; 
  for(my $j=0; $j<=$#data; $j++) {
    $playlistduration += $data[$j]->{Time}
  }

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "currentdir_playlist", $playlist);
  readingsBulkUpdate($hash, "currentdir_playlistduration", $playlistduration);
  readingsBulkUpdate($hash, "sortby",  "File");
  readingsBulkUpdate($hash, "status",  "idle");
  readingsEndUpdate($hash, 1);

  
  return undef;
}

#####################################
# Timeoutfunktion zur PlaylistInfo
####################################
sub MediaList_AbortFn($)     { 
  my ($hash) = @_;

  delete($hash->{helper}{RUNNING_PID});
  Log3 $hash->{NAME}, 2, "MediaList: BlockingCall for ".$hash->{NAME}." was aborted";
}


####################################
# Hauptfunktion zur Playlist 
# Rückgabe: JSON Object, für TabletUI Medialist
# keine Rekursion!
####################################
sub MediaList_CollectID3Tags ($) {
  my ($string) = @_;
  my @t = split(/\|/, $string);
  my $device = $t[0];
  my $object = $t[1];
  
  my @data;
  my $content;
  my $cover;
  my %covers; 
  my $fh;
  my $time = time();
  
  my $MediaList_CacheFileDir = AttrVal($device, "MediaList_CacheFileDir", "cache/");
  my $cofile = $MediaList_CacheFileDir.'covers.txt'; #Format: Artist;Album;Url

  return "Objekt ($object) exitiert nicht" unless (-e $object);

  #lade cover in das Hash
  if (-e $cofile) {
    open($fh, "<", $cofile) or die "Datei nicht gefunden";
    my @Zeilen = <$fh>;
    chomp(@Zeilen);
    close($fh);

    foreach(@Zeilen) {
      my @t = split(/;/,$_);
      $covers{uri_escape($t[0].$t[1])}=$t[2] if($t[2]);
    }
  }

  if (-f $object) {
    push(@data, MediaList_GetMP3Tags($device , $object));

  } elsif (-d $object) {
    my $allowedExtensions = AttrVal($device, "MediaList_allowedExtensions", ".*");

    opendir(my $dh, $object) || die "$object: $!";
    while(my $filename = readdir($dh)) {
      #undef($cover); $cover darf nicht gelöscht werden, das erste gefundene Cover für diesen Folder soll für den Rest weiterverwendet werden
      if($filename !~ m/^[\.]+/) {
        #Log3 $device, 3, "$device -> Datei: ".$filename; 
        $content = MediaList_GetMP3Tags($device, $object."/".$filename);
        if($content) {
          Log3 $device, 4, "MP3-Tags für \"".$object."/".$filename."\" gefunden: ".$content->{Artist}. " , " .$content->{Album};
          $cover = $covers{uri_escape($content->{Artist}.$content->{Album})} if($covers{uri_escape($content->{Artist}.$content->{Album})});
          if (!$cover) {
             Log3 $device, 4, "Lade Cover: ".$content->{Artist}. " , " .$content->{Album};
             $cover = MediaList_GetCover($device, $content->{File}, $content->{Artist}, $content->{Album});
             $cover="images/cd-empty.png" if(!$cover);
             $covers{uri_escape($content->{Artist}.$content->{Album})} = $cover;
          }
          $content->{Cover}=$cover;
          Log3  $device, 5, "CollectID3Tags: ".Dumper($content);
          push(@data, $content);
		      # informiere Parent, aktualisiere playlist wenn Ausführung > 1sek
		      if(time() - $time >= 1) {
		        # manchmal wird danach die gesamte Liste nicht nochmal erneuert sodass diese unvollständig bleibt :(
            #BlockingInformParent("MediaList_readingsSingleUpdateByName", [$device, "currentdir_playlist", JSON::XS->new->encode(\@data)], 0);
		        $time = time();
		      }
        }
      } 
    }
    closedir($dh); # nicht vergessen
  }

  return $device ."|" . JSON::XS->new->encode(\@data);
}

####################################
# Unterfunktion zur PlaylistInfo
# Rückgabe -> Array: 
# {"Artist":"abc", "Title":"def", "Album":"yxz", "Time":"123", "File":"spotify:track:123456", "Track":"1", "Cover":"https://...." }
####################################
sub MediaList_GetMP3Tags($$) {
  my ($device, $file) = @_;
  my $hash = $defs{$device};
  my $mp3;
  my $res;

  return undef if ($file !~ m/(\.mp3|\.m4a)$/i);   # keine mp3 Endung         
  return undef if (-d $file);              # ist Verzeichnis
  return undef if not (-f $file);          # ist keine Datei

#  $file =~ s/([\(\)\s])/\\$1/g; # alle Zeichen:(,)," " entfernen  

  if ($mp3 = MP3::Tag->new($file)) {
    my ($title, $track, $artist, $album, $comment, $year, $genre) = $mp3->autoinfo();
    my $mp3info = get_mp3info($file);
    my $duration = round($mp3info->{SECS}, 0);

    utf8::encode($title);
    utf8::encode($artist);
    utf8::encode($album);
    utf8::encode($comment);

    $res = {"Artist" => $artist, "Title" => $title, "Album" => $album, "Time" => $duration, "File" => $file, "Cover" => ""};
    Log3  $hash, 5, "GetMP3Tags: ".Dumper($res);

    return $res;
  }
  return undef;
}

######################
# https://www.allcdcovers.com/api
######################
sub MediaList_GetCover($$$$) {
  my ($device, $filename, $artist, $album) = @_;
  my $cover; 
  my $fh;
  

  my $MediaList_CacheFileDir = AttrVal($device, "MediaList_CacheFileDir", "cache/");
  my $file = $MediaList_CacheFileDir.'covers.txt'; #Format: Artist;Album;Url

  # Todo persistente Speicherung der Cover
  $cover = MediaList_CheckCoverAtPath($device, $filename);
  $cover = MediaList_DownloadCover($device, $artist, $album) if(!$cover);
  
  if ($cover && (length($artist) > 0 || length($album) > 0 )) {
    open($fh, ">>", $file) or die "Datei nicht gefunden";
    #Format: Artist;Album;Url
    print $fh $artist .";". $album .";". $cover ."\n";
    close($fh);
  }
  return $cover;
}

####################################
# Download von Covern
# https://www.apple.com/itunes/affiliates/resources/documentation/itunes-store-web-service-search-api.html
# http://www.myuuzik.de/index.php?SearchIndex=Music&Keywords=4+strings+Turn+It+Around
# https://www.google.de/search?q=cover+strumbellas+spirit&tbm=isch
# https://duckduckgo.com/?q=rhianna+unfaithful&iax=1&ia=images
# 
# TODO
# https://www.allcdcovers.com/api
# https://musicbrainz.org/doc/Cover_Art_Archive/API
# 
# über den Schlüssel von %params wird die Priorität der Datenabfrage gesteuert
# zb. 2_itunes -> Prio 2, erste wenn myuuzik nichts gefunden hat
#
# 3. Spotify: http://jsfiddle.net/JMPerez/0u0v7e1b/
#    https://developer.spotify.com/web-api/
#
# 4. LastFM
#    http://www.last.fm/api
####################################
sub MediaList_DownloadCover($$$) {
  my ($device, $artist, $album) = @_;
  my $hash = $defs{$device};
  my $HttpResponse;
  my $HttpResponseErr;
  my @matches;

  my $search = "";
  $artist = undef if (lc($artist) =~ m/various/);  
  $search .= $artist ." " if($artist);
  $search .= $album;
  $search =~ s/\W/ /g; # alle sonderzeichen entfernen  

  my %params = ("1_myuuzik" => {"baseurl"=> "http://www.myuuzik.de/index.php?SearchIndex=Music",
                              "term"     => "&Keywords=" . uri_escape($search),
                              "pattern"  => "img src=\"(http:\/\/ecx\.images-amazon\.com\/images[^\"]+)\"",},
                "3_itunes"  => {"baseurl"=> "https://itunes.apple.com/search?",
                              "term"     => "term=" . uri_escape($search),
                              "pattern"  => "\"artworkUrl100\"\:\"(http[^\"]+)\"",},
                "2_spotify" => {"baseurl"=> "https://api.spotify.com/v1/search?type=album&",
                              "term"     => "q=" . uri_escape($search),
                              "pattern"  => "\"url\"\ : \"(http[^\"]+)\"",},
                "3_lastfm_1"=> {"baseurl"=> "http://ws.audioscrobbler.com/2.0/?method=album.search&api_key=f3a26c7c8b4c4306bc382557d5c04ad5&",
                              "term"     => "album=" . uri_escape($album),
                              "pattern"  => "\<image\ size=\"extralarge\">(.+)<\/image>",},
               );  

  foreach my $engine (sort keys(%params)) {

    my $url  = "$params{$engine}{baseurl}" . "$params{$engine}{term}";
    Log3 $device, 4, "DownloadCover: Hole URL: ". $url;

    my $param = {     url         => $url,
                      timeout     => 5,
                      hash        => $hash,    # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
                      method      => "GET",     # Lesen von Inhalten
                      header     => "User-Agent: Mozilla/5.0 (Windows NT 6.2; Win64; x64; rv:10.0) Gecko/20100101 Firefox/10.0"
                  };
    ($HttpResponseErr, $HttpResponse) = HttpUtils_BlockingGet($param);
    
    if(length($HttpResponseErr) > 0) {
      Log3 $device, 3, "GetCover: Fehler beim abrufen der Daten";
      Log3 $device, 3, "GetCover: " . $HttpResponseErr; 
    } 
#return Dumper($HttpResponse);    
    @matches = ( $HttpResponse =~ /$params{$engine}{pattern}/igm );
#return Dumper(@matches);
    last if($matches[0]);
  }
 
  if($matches[0]) {
    return $matches[0];
  } else {
    Log3 $device, 4, "GetCover: Cover nicht auffindbar: ".$search;
    return undef;
  }
}

####################################
# Funktion checkt, ob im angegebenen Pfad 
# eine CoverDatei liegt
####################################
sub MediaList_CheckCoverAtPath($$) {
  my ($device, $fullfile) = @_;
  my $cover;
  #my $PathReplaceFrom = "/media/music/";
  #my $PathReplaceTo   = "https://192.168.10.30/music/";
  my $PathReplaceFrom     = AttrVal($device, "MediaList_PathReplaceFrom", undef);
  my $PathReplaceTo       = AttrVal($device, "MediaList_PathReplaceToPic", undef);

  my($file, $dir, $ext) = fileparse($fullfile, qr"\..[^.]*$");

  opendir(my $dh, $dir) || die "$dir: $!";
  while(my $filename = readdir($dh)) {
    Log3 $device, 5, "Checke Cover in $dir: $filename";
    if(lc($filename) =~ m/front.*\.jpg/ || lc($filename) =~ m/cover.*\.jpg/) {
      $cover = $dir.$filename;
      $cover =~ s/^($PathReplaceFrom)/$PathReplaceTo/ if ($PathReplaceFrom && $PathReplaceTo);
      return $cover;
    }
  }
  
  closedir($dh);

  return undef;
}

####################################
# Aus dem BlockingCall Readings aktualisieren
####################################
sub MediaList_readingsSingleUpdateByName($$$) {
  my ($devName, $readingName, $readingVal) = @_;
  my $hash = $defs{$devName};
  #Log3 $hash, 4, "MediaList_readingsSingleUpdateByName: Dev:$devName Reading:$readingName Val:$readingVal";
  readingsSingleUpdate($defs{$devName}, $readingName, $readingVal, 1);
}

####################################
# die PlayList sortieren, Parameter
# 1. Hash
# 2. SortiTem: Filename, Title
# 3. order: asc, desc
####################################
sub MediaList_playlist_sort {
  my ($json, $SortItem, $order) = @_; 
  my @t;
  my @sortdata;

  my @data = @{JSON::XS->new->decode($json)};
#  Log3 undef, 1, "JSON: ".Dumper($json);
#  Log3 undef, 1, "DATA: ".Dumper(@data);

  for(my $j=0; $j<=$#data; $j++) {
    push(@t, $data[$j]->{$SortItem});
  }

  @t = sort(@t);
  @t = reverse @t if($order eq "desc");

  for(my $i=0; $i<=$#t; $i++) {
    for(my $j=0; $j<=$#data; $j++) {
      if($t[$i] eq $data[$j]->{$SortItem}) {
       push(@sortdata, $data[$j]);
      }
    }
  }

  return JSON::XS->new->encode(\@sortdata);
}


####################################
# CrawlerRoutine zur Navigation im 
# Verzeichnis
####################################
sub MediaList_Crawl($$) {
  my ($hash, $startdir) = @_;
  #my @e = split(/:\ /, $event);
  #my $startdir = $e[1];
  my @list; 
  my $SelItem;
  my $cmdBack = "Back";
  my $FolderIdent = "*";

  my $me = $hash->{NAME};
 

  $startdir = "/" if ($startdir eq "");
  my $CurDir = ReadingsVal($me, "CurrentDir", "/");
  $startdir =~ s/^\*(.*)/$1/g; # FolderIdent wieder entfernen

  if ($startdir eq $cmdBack) {
    my @dir = split("/", $CurDir);
    pop(@dir);
    $startdir = join("/", @dir) if ($#dir > 0);
    $startdir = "/" if ($#dir == 0);
    $SelItem= $startdir;
  } elsif (!(-d  $startdir || -d $CurDir."/".$startdir)) {
    # Datei anstatt Verzeichnis ausgewählt
    $SelItem= $CurDir."/".$startdir;
    $startdir = $CurDir;
  } elsif ($startdir =~ m/^\//) {
    # absoluter Pfad angegeben
    $startdir = $startdir;
    $SelItem= $startdir;
  } else {
    # relativer Pfad
    $startdir = $CurDir."/".$startdir; 
    $startdir =~ s/^\/\//\//g;
    $SelItem= $startdir;
  }

  $startdir = $hash->{ROOT} unless ($startdir =~ m/^($hash->{ROOT})/);

  if (-d $startdir) { 
    my $allowedExtensions = AttrVal($me, "MediaList_allowedExtensions", ".*");

    opendir(my $dh, $startdir) || die "$startdir: $!";
    while(my $filename =  readdir($dh)) {
      #-- PAH
      if( ($filename !~ m/^\..*/) && (-d $startdir."/".$filename) ) {
        $filename = $FolderIdent . $filename;
        push(@list, $filename);
      } 
    }
    closedir($dh); # nicht vergessen
  } 

  @list=sort(@list);
  unshift(@list, $cmdBack) unless($startdir eq $hash->{ROOT});

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "FolderContent",  join(":", @list));
  readingsBulkUpdate($hash, "CurrentDir", $startdir);
  readingsBulkUpdate($hash, "SelectedItem", $SelItem);
  readingsEndUpdate($hash, 1);
  
  return undef;
}


##################################### 
1;

=pod
=item helper
=item summary    Creates a playlist based on a local media share for submission to an arbitrary device
=item summary_DE Erstellt eine Playlist einem lokalen Musikverzeichnis zur Übergabe an ein beliebiges Device
=begin html

<a name="MediaList"></a>
<h3>MediaList</h3>
<ul>
  This module allows to navigate trough a locally connected
  music library. It can compile complex playlists and also allows a quick playing of 
  a selected directory
  <br>
  Note: this module needs the following additional Perl modules:<br>
  <ul>
    <li>libmp3-tag-perl</li> 
    <li>libjson-xs-perl</li> 
    <li>libmp3-info-perl</li>
  </ul>
  <br>
  <br>
  <a name="MediaList define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MediaList &lt;root path&gt; </code>
    <br><br>
    Defines an instance of MediaList. The root path denotes the top directory.
    <br>
    Example:
    <ul>
      <code>define MyMediaList MediaList /media/music</code><br>
    </ul>
  </ul>
  <br> 

  <a name="MediaListReadings"></a>
  <b>Readings</b><br>
  <ul>
    <li><b>CurrentDir</b>:the current directory</li>
    <li><b>FolderContent</b>:the folder content of CurrentDir</li>
    <li><b>SelectedItem</b>:the last selected item from FolderContent</li>
    <li><b>currentdir_playlist</b>:playlist of CurrentDir</li>
    <li><b>currentdir_playlistduration</b>:duration of currentdir_playlist</li>
    <li><b>playlist</b>:actual playlist ;)</li>
    <li><b>playlistduration</b>:duration of actual playlist</li>
  </ul>
  <br>

  <a name="MediaListset"></a>
  <b>Set</b> 
  <ul>
    <li><b>RequestedDirectory</b><br>
      Moving to given relative directory. An record of Reading <i>FolderContent</i> must be used.
      <br>Example:<br>
      <ul>
        <code>set &lt;MyMediaList&gt; RequestedDirectory AbbaMusic</code><br>
      </ul>
    </li>

    <li><b>Play currentdir|playlist [&lt;device&gt;]</b><br>
      Submit the playlist to the target device. If the second parameter is <b>currentdir</b>, this will be the complete content of the current directory, see reading <i>currentdir_playlist</i>. 
      If the second parameter is <b>playlist</b> this will be the playlist created with the module, see reading <i>playlist</i>
      The third parameter is optional and denotes the target device. This will overwrite the value of the attribute MediaList_PlayerDevice.
      <br>Examples:<br>
      <ul>
        <code>set &lt;MyMediaList&gt; Play currentdir SoundTouch.EG</code><br>
        <code>set &lt;MyMediaList&gt; Play playlist</code><br>
      </ul>
    </li>

    <li><b>Playlist_New</b><br>
      Creates a new playlist.
      <br>Example:<br>
      <ul>
        <code>set &lt;MyMediaList&gt; Playlist_New MyNewPlaylist</code><br>
      </ul>
    </li>

    <li><b>Playlist_Add [&lt;number&gt;] [a|i]</b><br>
      If the value of the second parameter is a=add or missing, the 
      track with the given number or the complete CurrentDir are added to the playlist<br>
      If the value of the second parameter is i=immediately, the current filename is passed to the 
      <br>Example:
      <ul>
        <code>set &lt;MyMediaList&gt; Playlist_Add 0</code><br>
        Add first track from reading <i>currentdir_playlist</i> to the playlist<br>
        <code>set &lt;MyMediaList&gt; Playlist_Add</code><br>
        Add all tracks from reading <i>currentdir_playlist</i> to the playlist<br>
      </ul>
    </li>

    <li><b>Playlist_Del</b><br>
      Deletes a track from the playlist.
      <br>Example:<br>
      <ul>
        <code>set &lt;MyMediaList&gt; Playlist_Del 0</code><br>
        Drops the first track from the playlist
      </ul>
    </li>

    <li><b>Playlist_Empty</b><br>
      Clears the content of the playlist
    </li>
    
     <li><b>Playlist_Save</b><br>
      Saves the playlist under the given name &lt;MediaList_PathReplaceTo&gt;&lt;Playlist_Name&gt;.m3u
    </li>
     <li><b>Playlist_Read</b><br>
      Reads a playlist with the given name &lt;MediaList_PathReplaceTo&gt;&lt;Playlist_Name&gt;.m3u
    </li>

    
  </ul>
  <br> 

  <a name="MediaListget"></a>
  <b>Get</b> 
  <ul>N/A</ul><br> 

  <a name="MediaListattr"></a>
  <b>Attributes</b>
  <ul>
    <li><b>MediaList_PlayerDevice</b><br>
      Definition of the target player device (may be overwritten by the set .. Play command).
      <br>Example:
      <ul>
        <code>attr &lt;MyMediaList&gt; MediaList_PlayerDevice Sonos_LivingRoom</code><br>
        <br>
      </ul>
    </li>  
     <li><b>MediaList_PlayerType</b><br>
      Definition of your target player type - can be SONOS, BOSE or MPD
    </li> 
    <li><b>MediaList_PathReplaceFrom</b><br>
      Rewrite the local media path to a path accessible by the target device, FROM pattern
    </li>
    <li><b>MediaList_PathReplaceTo</b><br>
      Rewrite the local media path to a path accessible by the target device, TO pattern.
      If this TO pattern is omitted, the local media path is simply erased.
    </li>
    <li><b>MediaList_PathReplaceToPic</b><br>
      Rewrites the local cover path to a path accessible by web browser and TabletUI, TO pattern.
      The FROM pattern is defined by <i>MediaList_PathReplaceFrom</i>
    </li>
    <li><b>MediaList_PlayerStartCommand</b><br>
      Definition of the start command to play a playlist on your target device. This command may contain the strings <code>&lt;fullfile&gt;</code>, 
      which on execution are replaced by the filename of the playlist.
    <li><b>MediaList_PlayerImmediateCommand</b><br>
      Definition of the command to play a file immediately on your target device. This command may contain the strings <code>&lt;fullfile&gt;</code>, 
      which on execution are replaced by the filename of the playlist. 
    </li>   
    <li><b>MediaList_CacheFileDir</b><br>
      Definition of your cache directory, in which the playlist.m3u will be created. In case of symlinks or 
      music-copies, this directory will be used
      <br>Example:
      <ul>
        <code>attr &lt;MyMediaList&gt; MediaList_CacheFileDir /var/lib/mpd/playlists/</code><br>
        <code>attr &lt;MyMediaList&gt; MediaList_CacheFileDir cache/</code><br> 
      </ul>
    </li>

    <li><b>MediaList_mkTempCopy</b><br>
      Specify if you want a playlist with remote files or locally accessible files.<br>
      In case of using a SONOS or BOSE device, a remote file based playlist is sufficient.<br>
      In case of using an MPD, local files in MPD music directory must be used
      <br>Example:
      <ul>
        <code>attr &lt;MyMediaList&gt; MediaList_mkTempCopy none</code><br>
        In case of a SONOS or BOSE device<br>
        <code>attr &lt;MyMediaList&gt; MediaList_mkTempCopy symlink</code><br> 
        In case of an MPD device -- what ??
      </ul>
    </li>

  </ul>
</ul>

=end html
=begin html_DE

<a name="MediaList"></a>
<h3>MediaList</h3> 
  <br>
  Eine deutsche Beschreibung ist aktuell nur im WIKI verfügbar.<br>
  <a href="https://wiki.fhem.de/wiki/MediaList">Wiki MediaList</a>

=end html_DE
=cut
