#!/usr/bin/perl

# Use section
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
my $debug = 0;
my $result;

# Script data
my $Gthreshold = 2;
my $HalfsToCheck = 2;
my $YearsToCheck = 1;


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
	%stockclose = {};
	
	# Get last date on the trade
	$sql = "select max(date) from daily";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	@row = $sth->fetchrow_array();
	$date = $row[0];
	$sth->finish();

	# Get list of stocks traded last date
	$sql = "select code, close from daily where date = '$date' and code like '___' order by code";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	while(@row = $sth->fetchrow_array())
	{
		$code = $row[0];
		$close = $row[1];
		$stockclose {$code} = $close;
	}
	$sth->finish();

	foreach $code ( sort keys %stockclose )
	{
		# Lets think it is good
		$good = 0;
		
		@EPSG = ();
		
		# Get half year growth figures
		$sql = "select eps, epsg, date from fundamentals where code = '$code' and period = 'half' order by date desc";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		while(@row = $sth->fetchrow_array()) {
			$good = 1;
			push @EPS, $row[0];
			push @EPSG, $row[1];
		}
		$sth->finish();
		$halfs = scalar(@EPSG);
		if ( $halfs > $HalfsToCheck ) { $halfs = $HalfsToCheck; }

		if ( $good )
		{
			# First, lets see if growth figures are better than growth threshold
			for ( $i = 0; $i < $halfs; $i++ )
			{
				if ( $EPSG[$i] < $Gthreshold ) { $good = 0; }
			}
		}
		$EPSGHalf = $EPSG[0];

		if ( $good )
		{
			# Now, lets see if EPSG is accelerating
			$ThisEPSG = $EPSG[0];
			for ( $i = 1; $i < $halfs; $i++ )
			{
				$PreviousEPSG = $EPSG[$i];
				if ( $ThisEPSG < $PreviousEPSG ) { $good = 0; }
				$ThisEPSG = $PreviousEPSG;
			}
		}

		$years = 0;
		@EPSG = ();
		@SalesG = ();
		@RoE = ();
		@Margin = ();

		if ( $good )
		{
			# Now, lets get yearly figures
			$sql = "select epsg, salesg, roe, margin from fundamentals where code = '$code' and period = 'full' order by date desc";
			$sth = $dbh->prepare($sql);
			$result = $sth->execute();
			while( @row = $sth->fetchrow_array() )
			{
				push @EPSG, $row[0];
				push @SalesG, $row[1];
				push @RoE, $row[2];
				push @Margin, $row[3];
			}
			$sth->finish();
			$years = scalar(@EPSG);
			if ( $years > $YearsToCheck ) { $years = $YearsToCheck; }
		}
			
		if ( $good )
		{
			# Lets see if EPS yearly growth figures are better than growth threshold
			for ( $i = 0; $i < $years; $i++ )
			{
				if ( $EPSG[$i] < $Gthreshold ) { $good = 0; }
			}
		}
		
		if ( $good )
		{
			# Now, lets see if RoE is good
			for ( $i = 0; $i < $years; $i++ )
			{
				if ( $RoE[$i] < $Gthreshold ) { $good = 0; }
			}
		}

		if ( $good )
		{
			# Now, lets see if Margin is good
			for ( $i = 0; $i < $years; $i++ )
			{
				if ( $Margin[$i] < $Gthreshold ) { $good = 0; }
			}
		}

		if ( $good )
		{
			# Now, lets see if Sales are good
			for ( $i = 0; $i < $years; $i++ )
			{
				if ( $SalesG[$i] < $Gthreshold ) { $good = 0; }
			}
		}

		if ( $good )
		{
			# Now, lets see if the price is good
			if ( $stockclose {$code} < $Gthreshold ) { $good = 0; }
		}
		if ( $good ) { $flag = "GOOD"; } else { $flag = "----"; }
		if ( $debug and ! $good)
		{
			print "$flag: $code: Close = ".$stockclose {$code}.", Half = $EPSGHalf, Full = ".$EPSG[0].", SalesG = ".$SalesG[0].", RoE = ".$RoE[0].", Margin = ".$Margin[0]."\n";
		}
		if ( $good )
		{
			print "$flag: $code: Close = ".$stockclose {$code}.", Half = $EPSGHalf, Full = ".$EPSG[0].", SalesG = ".$SalesG[0].", RoE = ".$RoE[0].", Margin = ".$Margin[0]."\n";
		}
		
	}
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