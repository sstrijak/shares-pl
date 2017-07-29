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
$testcode = "";
$MaxPE=15;
$MinAssetOverLias = 1.5;
$MaxTotalDebtOverNCA = 1.1;
$MaxPriceOverNTA = 1.2;
$YearsToCheckEarnings = 3;
my @codes;
my @earnings;
my $earnyears;

my $histselect = "";

my %historicals;
my %financials;
my %balance;
my %capital;

########## Read parameters and display help message

$CheckYear = $year;
if ( defined ( $ARGV[0] ) ) {
	$CheckYear = $ARGV[0];
}

open LOG, ">>", $logfile;
print LOG "Stage\tCode\tData1\tValue1\tData2\tValue2\tRatio\tTarget\tMiss\tPrice Target\n";
print LOG "$year-$month-$day for $CheckYear";

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

$select = "";
foreach $field ( @fields ) {  $select .= $field.","; }

if ($keepgoing)
{
	if ( $testcode )
	{
		$codes[0]=$testcode;
	}
	else
	{
		# Get list of stocks with data at $CheckYear
		$sql = "select distinct code from historicals where date <= '$CheckYear-06-30' and date > '".($CheckYear-1)."-06-30'";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		$codecount = 0;
		while(@row = $sth->fetchrow_array())
		{
			$codes[ $codecount++ ] = $row[0];
		}
		$sth->finish();
	}

	foreach $code ( @codes )
	{
		print $code."\n";
		#Reset data
		for ( $i=0; $i < $earnyears; $i++ ) { $earnings[$i] = 0; }
		$earnyears = 0;
		%stock = {};
		
		$checkfail = 0;
		$codefail = 0;

		$sql = "select close from daily where code='$code' and date <= '$CheckYear-06-30' order by date desc limit 1";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		@row = $sth->fetchrow_array();
		$close = $row[0];
		$sth->finish();
		
		$sql = "select avg(earn) from historicals where code='$code' and date <= '$CheckYear-06-30' order by date desc limit $YearsToCheckEarnings";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		@row = $sth->fetchrow_array();
		$aveearn = $row[0];
		$sth->finish();
		
		$sql = "select tassets, tliablts from balance where code='$code' and date <= '$CheckYear-06-30' order by date desc limit 1";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		@row = $sth->fetchrow_array();
		$stock{'tassets'} = $row[0];
		$stock{'tliablts'} = $row[1];
		$sth->finish();

		$sql = "select tdebt from capital where code='$code' and date <= '$CheckYear-06-30' order by date desc limit 1";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		@row = $sth->fetchrow_array();
		$stock{'tdebt'} = $row[0];
		$sth->finish();

		$sql = "select divs, shares, nta from historicals where code='$code' and date <= '$CheckYear-06-30' order by date desc limit 1";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		@row = $sth->fetchrow_array();
		$stock{'divs'} = $row[0];
		$stock{'shares'} = $row[1];
		$stock{'nta'} = $row[2];
		$sth->finish();

		#Earnings stability: No deficit in the last five years.
		$sql = "select earn from historicals where code='$code' and date <= '$CheckYear-06-30' order by date desc limit $YearsToCheckEarnings";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		while(@row = $sth->fetchrow_array())
		{
			$earn = $row[0];
			$earnings[ $earnyears++ ] = $earn;
			if ( $earn <= 0) { $checkfail = 1; }
		}
		$sth->finish();

		if ( $checkfail )
		{
			print LOG "X1\t$code\tearning deficit ";
			for ( $i=0; $i < $earnyears; $i++ ) { print LOG "$earnings[$i], "; }
			print LOG "\n";
			$codefail = 1; $checkfail = 0; 
		}


		# PE = Price / earning average over 3 yr
		if ( $aveearn != 0 )
		{
			$pe = $close / $aveearn;
			if ( $pe <= 0 or $pe > $MaxPE ) { $checkfail = 1; }
		}
		else { $checkfail = 1; }
		if ( $checkfail )
		{
			print LOG "X3\t$code\tClose\t$close\taveearn\t$aveearn\t$pe\t>$MaxPE\t".($pe/$MaxPE)."\t".($aveearn*$MaxPE)."\n";
			$codefail = 1; $checkfail = 0; 
		}


		#(a) Current assets at least 1 ½ times current liabilities
		$AssetOverLias = 0;
		if ( $stock{'tliablts'} > 0) 
		{
			$AssetOverLias = $stock{'tassets'} / $stock{'tliablts'}; 
			if ( $AssetOverLias <  $MinAssetOverLias ) { $checkfail = 1; }
		}
		else { $checkfail = 1; }
		if ( $checkfail )
		{
			print LOG "X4\t$code\tassets\t$stock{'tassets'}\tliabilities\t$stock{'tliablts'}\t$AssetOverLias\t>$MinAssetOverLias\t".($AssetOverLias/$MinAssetOverLias)."\n"; 
			$codefail = 1; $checkfail = 0; 
		}

		#(b) debt not more than 110% of net current assets (for industrial companies).
		# net current assets (working capital) = net current assets - current liabilities
		$NetCurrentAssets = $stock{'tassets'} - $stock{'tliablts'};
		$TotalDebtOverNCA = 0;
		if ( $NetCurrentAssets > 0)
		{
			$TotalDebtOverNCA = $stock{'tdebt'} / $NetCurrentAssets;
			if ( $TotalDebtOverNCA > $MaxTotalDebtOverNCA ) { $checkfail = 1; }
		}
		else { $checkfail = 1; }
		if ( $checkfail )
		{	print LOG "X5\t$code\ttotal debt\t$stock{'tdebt'}\tNetCurrentAssets\t$NetCurrentAssets\t$TotalDebtOverNCA\t<$MaxTotalDebtOverNCA\t".($TotalDebtOverNCA/$MaxTotalDebtOverNCA)."\n"; 
			$codefail = 1; $checkfail = 0; 
		}

		#Dividend record: Some current dividend. 
		if ( $stock{'divs'} <= 0 )
		{
			print LOG "X6\t$code\tdivs\t$stock{'divs'}\n";
			$codefail = 1;
		}

		#Earnings growth: Last year’s earnings more than those of 5yr ago. 
		if ( $earnings[0] <= $earnings[$earnyears-1] )
		{
			print LOG "X7\t$code\tearning growth ";
			for ( $i=0; $i < $earnyears; $i++ ) { print LOG "$earnings[$i], "; }
			print LOG "\n";
			$codefail = 1;
		}

		#Price: Less than 120% net tangible assets.
		
		$PriceOverNTA = 0;
		if ( $stock{'nta'} > 0 )
		{
			$PriceOverNTA = $close / $stock{'nta'} ;
			if ( $PriceOverNTA > $MaxPriceOverNTA )  { $checkfail = 1; }
		}
		else { $checkfail = 1; }
		if ( $checkfail )
		{ 
			print LOG "X8\t$code\tPrice\t$close\tNetTangibleAssets\t$stock{'nta'}\t$PriceOverNTA\t<$MaxPriceOverNTA\t".($PriceOverNTA/$MaxPriceOverNTA)."\t".($stock{'nta'}*$MaxPriceOverNTA)."\n"; 
			$codefail = 1; $checkfail = 0; 
		}

		if ( not $codefail ) { print LOG "V!\t$code\n"; }
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