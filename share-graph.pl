#!/usr/bin/perl
# Use section

use List::Util qw(min max);
use GD::Graph::ohlc;
use GD::Graph::mixed;

use Date::Calc qw(Today_and_Now);
use Date::Calc qw(Add_Delta_Days);
use Date::Calc qw(Day_of_Week);
use File::Copy;
use File::Basename;
use DBI;
use Net::SMTP;
use Net::SMTP::SSL;
use List::Util qw/min max sum/;
require './growth.pl';

$test = div0 (1.25,1);

# Date run and mypath
($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
my $starttime = "$year-$month-$day-$hour:$min:$sec";
my ($pname, $mypath, $type) = fileparse($0,qr{\..*});

# File and directories
$logfile = "$mypath/$pname.log";
$htmldir = "$mypath/html";

# SMTP
my $smtpserver = 'mail.7r.com.au';
my $smtpport = 465;
my $smtpuser   = 'shares@7r.com.au';
my $smtppassword = 'D3l3t312';
my $mailfrom = "shares\@7r.com.au";
my $mailto = "sstrijak\@7r.com.au";
my $subject = "$pname on $starttime";
my $message = "";

# mySQL
my $dbname = "shares";
my $dbhost = "localhost";
my $dbport = 3306;
my $dbuser = "shares";
my $dbpassword = "D3l3t312";
my $dbtable = "stocks";
my $sql;
my $sth;
my @row;

# Flow control and reporting
my $keepgoing = 1;
my $result;

# Script data
my $Nwk = 10;
my $Nday = 50;
my $stockcount = 0;

########## Read parameters and display help message

open LOG, ">>", $logfile;

my $dsn = "DBI:mysql:database=$dbname;host=$dbhost;port=$dbport";
my $dbh = DBI->connect($dsn, $dbuser, $dbpassword);
my $error = $dbh->{'mysql_error'};

if ( $error)
{
	$thismessage = "Error connecting to database: $error";
	logentry ( $thismessage );
	$message .= "$thismessage\n";
	$keepgoing = 0;
}

if ($keepgoing)
{
	@dates = ();
	@pricest = ();
	
	$sql = "select date, open, high, low, close, volume from stocks where code='BAL' order by date";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	while(@row = $sth->fetchrow_array())
	{
		$date = "$row[0]";
		$open = sprintf "%0.4f", $row[1];
		$high = sprintf "%0.4f", $row[2];
		$low = sprintf "%0.4f", $row[3];
		$close = sprintf "%0.4f", $row[4];
		$volume = $row[5];

		push @dates, $date;
		push @prices, [ $date,$open,$high,$low,$close ] ;
	}
	$sth->finish();

    my @all_points = map {@$_[1 .. 4]} @prices;
    my $min_point  = min(@all_points);
    my $max_point  = max(@all_points);

    my $graph = GD::Graph::mixed->new(800, 400);
       $graph->set( 
            x_labels_vertical => 1,
            x_label           => 'Trade Date',
            y_label           => 'BAL',
            title             => "Example OHLC",
            transparent       => 0,
            fgclr             => [qw(black)],
            dclrs             => [qw(lgray blue)],
            types             => [qw(lines ohlc)],
            y_min_value       => $min_point-0.2,
            y_max_value       => $max_point+0.2,
            y_number_format   => '%0.2f',
            x_label_skip      => 5,
            long_ticks        => 1,

        ) or warn $graph->error;

    my $data_ohlc = [
        [ map {$_->[0]} @prices ],       # date
        [ map {$_->[4]} @prices ],       # close
        [ map {[@$_[1 .. 4]]} @prices ], # ohlc
    ];

    $graph->plot($data_ohlc) or die $graph->error;

	my $file = 'bars.png';
	open(my $out, '>', $file) or die "Cannot open '$file' for write: $!";
	binmode $out;
	print $out $graph->gd->png;
	close $out;
	
	
}
$dbh->disconnect();

$message .= "Calculated averages for $stockcount stocksk\n";

# closing
# sendreport ( $message );
close LOG;

sub sendreport () {
	my $message = $_[0];
	my $smtp = Net::SMTP::SSL->new($smtpserver, Port=>$smtpport, Timeout => 10, Debug => 1);
	$smtp->auth($smtpuser,$smtppassword);
	$smtp->mail($mailfrom);
	$smtp->to($mailto);
	$smtp->recipient($mailto);
	$smtp->data();
	$smtp->datasend("To: $mailto\n");
	$smtp->datasend("From: $mailfrom\n");
	$smtp->datasend("Subject: $subject\n");
	$smtp->datasend("\n"); # done with header
	$smtp->datasend($message);
	$smtp->dataend();
	
	$smtpcode = $smtp->code();
	$smtpmsg = $smtp->message();
	
	$smtp->quit(); # all done. message sent.
	logentry ( "Mail send result: $smtpcode: $smtpmsg" );
}

sub logentry () {
	my $entry = $_[0];
	print STDOUT "$entry\n";
	($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
	$now = "$year-$month-$day-$hour:$min:$sec";
	print LOG $now; 
	print LOG ": $entry\n"; 
}

sub div0 () {
	my $num = $_[0];
	my $div = $_[1];
	if ( $div != 0 )
	{
		$div0 = $num/$div;
	}
	else
	{
		$div0 = 0;
	}
	return $div0;
}
