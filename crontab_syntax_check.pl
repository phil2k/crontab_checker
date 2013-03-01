#!/usr/bin/perl
#
# By Phil2k@gmail.com
#

use strict;
use warnings;
use Getopt::Std;

my @shell_commands=("cd");
my @months=("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec");
my @dows=("sun", "mon", "tue", "wed", "thu", "fri", "sat");
my $which_cmd="/usr/bin/which";

my $syntax="$0 [-n] [-u no|yes] [<cron_file>]\nWhere: -n = don't look for executables or user-names\n       -u no = crontab with no users (usual cron file)\n       -u yes = crontab with user-names (system cron file)";
local *FILE;

my %opts=();
$Getopt::Std::STANDARD_HELP_VERSION=1;
sub main::VERSION_MESSAGE() { print STDERR "crontab_syntax_check Version 1.1 by Phil2k\@gmail.com\n"; };
sub main::HELP_MESSAGE() { print STDERR $syntax."\n"; };
if (!getopts('nu:', \%opts)) {
  print STDERR $syntax."\n";
  exit(1);
  }
my $dont_check_exec_and_users=0;
my $cron_with_users="";
if (exists($opts{n})) { $dont_check_exec_and_users=1; }
if (exists($opts{u})) {
  if (defined($opts{u}) && ($opts{u}=~/^(on|yes)$/i)) { $cron_with_users=1; }
  elsif (defined($opts{u}) && ($opts{u}=~/^(off|no)$/i)) { $cron_with_users=0; }
  else {
    print STDERR $syntax."\n";
    exit(1);
    }
  }
if ($#ARGV<0) { # no more arguments
  if (-t STDIN) { # no file on stdin
    print STDERR "Expecting a crontab file to check ...\n$syntax\n";
    exit(1);
    } else {
    *FILE=*STDIN;
    }
  } else {
  open FILE, $ARGV[0] or die "Cannot open crontab-file ".$ARGV[0].": $!\n";
  }

my %vars;
my $line_no=0;
my $maybe_cron_with_users=0;
my $maybe_cron_without_users=0;
my @warnings=();
my @errors=();
while(!eof(FILE)) {
  my $line=<FILE>;
  chomp($line);
  $line_no++;
  my $org_line=$line;
  my $period="";
  my $user="";
  my $cmd="";
  my $params="";
  
  $line=~s/\\./_/g; # remove escaped characters !
  $line=~s/[#%].*$//; # remove comments and input data for crons
  next if ($line=~/^\s*$/); # skip empty lines
  if ($line=~/^([a-zA-Z][a-zA-Z_0-9]*)\s*=\s*(.*)/) { # variables declaration
    my $var=$1;
    my $val=$2;
    if (exists($vars{$var})) {
      push @warnings, "Already defined variable $var(=".$vars{$var}.") on line #$line_no: $line";
      next;
      }
    $vars{$var}=$val;
    if ($var eq "SHELL") {
      if (!-x $val) {
        push @warnings, "No such shell executabile file $val on line #$line_no: $line";
        next;
        }
      }
    next;
    }
  elsif ($line=~/^\@(reboot|yearly|annualy|monthly|weekly|daily|midnight|hourly)\s+(\S+)(.*)$/) {
    $period=$1;
    $cmd=$2;
    $params=$3;
    }
  elsif ($line=~/^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.+)$/) { # usual cron line ?!
    my $min=$1;
    my $hour=$2;
    my $dom=$3;
    my $mon=$4;
    my $dow=$5;
    my $rest=$6;
    my $err="";
    if (length($err = &check_range($min, 0, 59, 'min'))) {
      push @errors, "minute: ".$err." on line #$line_no: $line";
      #next;
      }
    if (length($err = &check_range($hour, 0, 23, 'hour'))) {
      push @errors, "hour: ".$err." on line #$line_no: $line";
      #next;
      }
    if (length($err = &check_range($dom, 1, 31, 'dom'))) {
      push @errors, "day of month: ".$err." on line #$line_no: $line";
      #next;
      }
    if (length($err = &check_range($mon, 1, 12, 'month'))) {
      push @errors, "month: ".$err." on line #$line_no: $line";
      #next;
      }
    if (length($err = &check_range($dow, 0, 7, 'dow'))) {
      push @errors, "day of week: ".$err." on line #$line_no: $line";
      #next;
      }
    if ($cron_with_users eq "") { # don't know if it's a cron with user or not => we detect it
      if ((!$maybe_cron_with_users) && ($rest=~/^([a-z0-9\.\-_]+)\s+(\S+)(?:\s+(.+))$/)) { # might have an user
        my $t_user=$1;
        my $t_cmd=$2;
        my $t_rest=$3;
        if ($dont_check_exec_and_users || (getpwnam($t_user) && (!length(&check_cmd($t_cmd))))) {
          if ($maybe_cron_without_users) {
            push @warnings, "Cannot determine if it's a system crontab (with user-names) or not ! Please add \"-u on/off\" paramter ! Line $line_no: $line";
            }
          $maybe_cron_with_users=1;
          }
        }
      elsif ((!$maybe_cron_without_users) && ($rest=~/^(\S+)(?:\s+(.+))$/)) { # might don't have an user
        my $t_cmd=$1;
        my $t_rest=$2;
        if ((!length(&check_cmd($t_cmd)))) {
          if ($maybe_cron_with_users) {
            push @warnings, "Cannot determine if it's a system crontab (with user-names) or not ! Please add \"-u on/off\" paramter ! Line $line_no: $line";
            }
          $maybe_cron_without_users=1;
          }
        }
      }
    if (($cron_with_users eq "1") || ($maybe_cron_with_users && (!$maybe_cron_without_users))) {
      if ($rest=~/^([a-z0-9\.\-_]+)\s+(\S+)(?:\s+(.+))?$/) {
        $user=$1;
        $cmd=$2;
        $params=$3;
        if ((!$dont_check_exec_and_users) && (!getpwnam($user))) {
          push @warnings, "No such user $user on line #$line_no: $line";
          }
        } else {
        push @errors, "Invalid crontab line on $line_no: $line";
        next;
        }
      }
    elsif (($cron_with_users eq "0") || ((!$maybe_cron_with_users) && $maybe_cron_without_users)) {
      if ($rest=~/^(\S+)(?:\s+(.+))?$/) {
        $cmd=$1;
        $params=$2;
        } else {
        push @errors, "Invalid crontab line on $line_no: $line";
        next;
        }
      }
    else {
      push @warnings, "Skip checking line $line_no: $line";
      next;
      }
    }
  
  if ($cmd ne "") {
    my $err=&check_cmd($cmd);
    if (length($err)) {
      push @warnings, $err." on line #$line_no: $line";
      next;
      }
    }
  }
close FILE;

my $err;
foreach $err (@warnings) {
  print "Warning: $err\n";
  }
foreach $err (@errors) {
  print STDERR "Error: $err\n";
  }
if ($#errors>-1) {
  my $err="This crontab might not be run at all, because found syntax errors !\n";
  print $err;
  print STDERR $err;
  exit 1;
  } else {
  exit 0;
  }
###########


sub in_array() {
  my ($el, $array_ref)=@_;
  my $cmp;
  foreach $cmp (@{$array_ref}) {
    return 1 if ($el eq $cmp);
    }
  return 0;
  }
sub array_index() {
  my ($el, $array_ref)=@_;
  my $i;
  for($i=0;$i<=$#{$array_ref};$i++) {
    return $i if ($el eq $array_ref->[$i]);
    }
  return -1;
  }

sub check_interval_number() {
  my ($int, $min, $max, $type)=@_;
  #print " >>> check_interval_number($int,$min,$max,$type)\n";
  if (($int=~/^\d+$/) && (($int<$min) || ($int>$max))) {
    return (-1,"$int is out of range ($min-$max)");
    }
  elsif ($int!~/^\d+$/) {
    $int=lc($int);
    if ($type eq 'month') {
      if (($int!~/^[a-z]{3}$/) || (!&in_array($int, \@months))) {
        return (-1,"$int is not a valid month name (".join(',', @months).")");
        }
      $int=1+&array_index($int, \@months);
      }
    elsif ($type eq 'dow') {
      if (($int!~/^[a-z]{3}$/) || (!&in_array($int, \@dows))) {
        return (-1,"$int is not a valid week-day name (".join(',', @dows).")");
        }
      $int=&array_index($int, \@dows);
      }
    else {
      return (-1, "$int must be a number between $min-$max");
      }
    }
  return ($int,"");
  }

sub check_range() {
  my ($range, $min, $max, $type)=@_;
  my $int;
  my $all=0;
  foreach $int (split(',', $range)) {
    if ($int eq '*') {
      if ($all) {
        return "'*' already specified in $range";
        }
      $all=1;
      }
    elsif ($int=~/^(\d+|[a-z]+)$/i) {
      ($int, $err) = &check_interval_number($int, $min, $max, $type);
      return $err if ($int<0);
      }
    elsif ($int=~/^(\d+|[a-z]+)-(\d+|[a-z]+)$/i) {
      my $x=$1;
      my $y=$2;
      ($x, $err) = &check_interval_number($x, $min, $max, $type);
      return "$range:$int:".$err if ($x<0);
      ($y, $err) = &check_interval_number($y, $min, $max, $type);
      return "$range:$int:".$err if ($y<0);
      }
    elsif ($int=~/^(\d+|[a-z]+|\*)\/(\d+)$/i) {
      my $x=$1;
      my $y=$2;
      if (($x ne '*')) {
        ($x, $err) = &check_interval_number($x, $min, $max, $type);
        return "$range:$int:".$err if ($x<0);
        }
      ($y, $err) = &check_interval_number($y, $min, $max, '');
      return "$range:$int:".$err if ($y<0);
      }
    elsif ($int=~/^(\d+|[a-z]+)-(\d+|[a-z]+)\/(\d+)$/i) {
      my $x=$1;
      my $y=$2;
      my $z=$3;
      ($x, $err) = &check_interval_number($x, $min, $max, $type);
      return "$range:$int:".$err if ($x<0);
      ($y, $err) = &check_interval_number($y, $min, $max, $type);
      return "$range:$int:".$err if ($y<0);
      ($z, $err) = &check_interval_number($z, $min, $max, '');
      return "$range:$int:".$err if ($z<0);
      }
    else {
      return "$int is not a valid crontab period (*,$min-$max)";
      }
    }
  return "";
  }

sub check_cmd() {
  my ($cmd)=@_;
  return "" if ($dont_check_exec_and_users);
  if ($cmd=~/\//) { # contain / (path separator)
    if (!-x $cmd) {
      return "No such executable $cmd";
      }
    }
  elsif (!&in_array($cmd, \@shell_commands)) { # not in well known shell commands, try to search with "which"
    my $exec=$which_cmd." ".$cmd;
    my $result=qw!$exec!;
    if (($?>0) || ($result ne "")) {
      return "No such command $cmd";
      }
    }
  return "";
  }
