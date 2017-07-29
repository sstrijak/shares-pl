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
my $result;

# Script data
my $Nwk = 10;
my $Nday = 50;
my $RSNwk = 52;
my $RSNday = 250;
my $stockcount = 0;

%stocksondate = {};

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

$rscals = 0;
if ( $rscalcs )
{

	# Load XAO for RS calculations
	@xaoDdate = ();
	@xaoDclose = ();
	@xaoDvolume = ();
	%xaoDdates = {};
	@xaoWdate = ();
	@xaoWclose = ();
	@xaoWvolume = ();
	%xaoWdates = {};
	
	$sql = "select date, close, volume from daily where code='XAO' order by date";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	while(@row = $sth->fetchrow_array())
	{
		$date = $row[0];
		$price = $row[1];
		$volume = $row[2];

		push @xaoDdate, $date;
		push @xaoDclose, $price;
		push @xaoDvolume, $volume;
	}
	$sth->finish();

	for ( $i=0; $i < scalar (@xaoDdate); $i++)
	{
		$date = @xaoDdate[$i];
		$xaoDdates { $date } = $i;
	}

	$sql = "select date, close, volume from weekly where code='XAO' order by date";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	while(@row = $sth->fetchrow_array())
	{
		$date = $row[0];
		$price = $row[1];
		$volume = $row[2];

		push @xaoWdate, $date;
		push @xaoWclose, $price;
		push @xaoWvolume, $volume;
	}
	$sth->finish();

	for ( $i=0; $i < scalar (@xaoWdate); $i++)
	{
		$date = @xaoWdate[$i];
		$xaoWdates {$date} = $i;
	}

	# Load stocks

	$sql = "select distinct code from daily order by code";
	$sths = $dbh->prepare($sql);
	$result = $sths->execute();
	while(@srow = $sths->fetchrow_array())
	{

		$stockcount++;
		$code = $srow[0];
		print $code."\n";

		@stkDdate = ();
		@stkDopen = ();
		@stkDhigh = ();
		@stkDlow = ();
		@stkDclose = ();
		@stkDvolume = ();
		%stkDdates = {};
		@stkWdate = ();
		@stkWopen = ();
		@stkWhigh = ();
		@stkWlow = ();
		@stkWclose = ();
		@stkWvolume = ();
		%stkWdates = {};

		# Calculate daily averages

		$sql = "select date, open, high, low, close, volume from daily where code='$code' order by date";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		while(@row = $sth->fetchrow_array())
		{
			$date = $row[0];
			$open = $row[1];
			$high = $row[2];
			$low = $row[3];
			$close = $row[4];
			$volume = $row[5];

			push @stkDdate, $date;
			push @stkDopen, $open;
			push @stkDhigh, $high;
			push @stkDlow, $low;
			push @stkDclose, $close;
			push @stkDvolume, $volume;
		}
		$sth->finish();

		for ( $i=0; $i < scalar (@stkDdate); $i++)
		{
			$date = @stkDdate[$i];
			$stkDdates {$date} = $i;
		}

		$stop = 1;
		
		for ( $i = 0; $i < scalar (@stkDdate); $i++)
		{
			$date = @stkDdate[ $i ];
			
			$PNdayLow = mymin ( \@stkDlow, $i-$Nday, $i );
			$PNdayHigh = mymax ( \@stkDhigh, $i-$Nday, $i );
			$PNdayAve = myave ( \@stkDclose, $i-$Nday, $i );

			( $VNdayLow, $VNdayHigh, $VNdayAve ) = minmaxave ( \@stkDvolume, $i-$Nday, $i );

			$stockdate = $stkDdate[$i];
			$indexday = $xaoDdates{$stockdate};
			$stockROC = roc ( \@stkDclose, $i-$RSNday, $i );
			$indexROC = roc ( \@xaoDclose, $indexday-$RSNday, $indexday );
			$stockRS = div0 ( $stockROC, $indexROC );

			$sql = "UPDATE daily SET 
				`PNdayLow` = '$PNdayLow', `PNdayHigh` = '$PNdayHigh', `PNdayAve` = '$PNdayAve', 
				`VNdayLow` = '$VNdayLow', `VNdayHigh` = '$VNdayHigh', `VNdayAve` = '$VNdayAve',
				`rsnday` = '$stockRS'
				WHERE `code` = '$code'  and `date` = '$date'";
			my $sthu = $dbh->prepare($sql);
			$result = $sthu->execute();
			if ( ! $result )
			{
				$thismessage = $sthu->errstr.":".$sql;
				logentry ( $thismessage );
				$message .= $thismessage."\n";
			}
			$sthu->finish();
		}
		
		# Calculate weekly averages

		$sql = "select date, open, high, low, close, volume from weekly where code='$code' order by date";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		while(@row = $sth->fetchrow_array())
		{
			$date = $row[0];
			$open = $row[1];
			$high = $row[2];
			$low = $row[3];
			$close = $row[4];
			$volume = $row[5];

			push @stkWdate, $date;
			push @stkWopen, $open;
			push @stkWhigh, $high;
			push @stkWlow, $low;
			push @stkWclose, $close;
			push @stkWvolume, $volume;
		}
		$sth->finish();

		for ( $i=0; $i < scalar (@stkWdate); $i++)
		{
			$date = @stkWdate[$i];
			$stkWdates {$date} = $i;
		}

		$stop = 1;
		
		for ( $i = 0; $i < scalar (@stkWdate); $i++)
		{
			$date = @stkWdate[ $i ];
			
			$PNwkLow = mymin ( \@stkWlow, $i-$Nwk, $i );
			$PNwkHigh = mymax ( \@stkWhigh, $i-$Nwk, $i );
			$PNwkAve = myave ( \@stkWclose, $i-$Nwk, $i );

			( $VNwkLow, $VNwkHigh, $VNwkAve ) = minmaxave ( \@stkWvolume, $i-$Nwk, $i );

			$stockdate = $stkWdate[$i];
			$indexwk = $xaoWdates{$stockdate};
			$stockROC = roc ( \@stkWclose, $i-$RSNwk, $i );
			$indexROC = roc ( \@xaoWclose, $indexwk-$RSNwk, $indexwk );
			$stockRS = div0 ( $stockROC, $indexROC );

			$sql = "UPDATE weekly SET 
				`PNwkLow` = '$PNwkLow', `PNwkHigh` = '$PNwkHigh', `PNwkAve` = '$PNwkAve', 
				`VNwkLow` = '$VNwkLow', `VNwkHigh` = '$VNwkHigh', `VNwkAve` = '$VNwkAve',
				`RSNwk` = '$stockRS'
				WHERE `code` = '$code'  and `date` = '$date'";
			my $sthu = $dbh->prepare($sql);
			$result = $sthu->execute();
			if ( ! $result )
			{
				$thismessage = $sthu->errstr.":".$sql;
				logentry ( $thismessage );
				$message .= $thismessage."\n";
			}
			$sthu->finish();
		}
		
	}
	$sths->finish();
}

	# Calculate RS Index for last 10 days

	$sql = "select date,count(distinct code) from daily where code like '___' group by date order by date";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	while(@row = $sth->fetchrow_array())
	{
		$date = $row[0];
		$stocks = $row[1];
		$stocksondate { $date} = $stocks;
	}
	
	$stop = 1;
	
	$sql = "select distinct code from daily order by code";
	$sths = $dbh->prepare($sql);
	$result = $sths->execute();
	while(@srow = $sths->fetchrow_array())
	{
		$code = $srow[0];
		print "RSI: ".$code."\n";
		$sql = "select date, rsnday from daily where code='$code' and rsi = 0 order by date";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		while(@row = $sth->fetchrow_array())
		{
			$date = $row[0];
			$rsnday = $row[1];
			
			$sql = "select count(code) from daily where code like '___' and date='$date' and rsnday < $rsnday";
			$sthl = $dbh->prepare($sql);
			$result = $sthl->execute();
			@lrow = $sthl->fetchrow_array();
			$inferiorstocks = $lrow[0];
			$totalstocks = $stocksondate { $date };
			
			$rsi = $inferiorstocks / $totalstocks * 100;
			$sql = "UPDATE daily SET `RSI` = '$rsi' WHERE `code` = '$code'  and `date` = '$date'";
			my $sthu = $dbh->prepare($sql);
			$result = $sthu->execute();
		}
		$sth->finish();
	}
	$sths->finish();
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


sub minmaxave () {
	my $array = $_[0];
	my $start = $_[1];
	my $end = $_[2];
	
	if ( $start < 0 ) { $start = 0 }
	
	$min = @$array[$start];
	$max = @$array[$start];
	$sum = 0;
	
	for ( $mma = $start; $mma <= $end; $mma++ )
	{
		$val = @$array [ $mma ];
		if ( $min > $val ) { $min = $val; }
		if ( $max < $val ) { $max = $val; }
		$sum += $val;
	}
	$ave = $sum / ( $end - $start +1 );
	return ( $min, $max, $ave);
}

sub myave () {
	my $array = $_[0];
	my $start = $_[1];
	my $end = $_[2];
	
	if ( $start < 0 ) { $start = 0 }

	$sum = 0;
	for ( $mma = $start; $mma <= $end; $mma++ )
	{
		$val = @$array [ $mma ];
		$sum += $val;
	}
	$ave = $sum / ( $end - $start +1 );
	return $ave;
}


sub mymin () {
	my $array = $_[0];
	my $start = $_[1];
	my $end = $_[2];
	
	if ( $start < 0 ) { $start = 0 }
	$min = @$array[$start];
	for ( $mma = $start; $mma <= $end; $mma++ )
	{
		$val = @$array [ $mma ];
		if ( $min > $val ) { $min = $val; }
	}
	return $min;
}

sub mymax () {
	my $array = $_[0];
	my $start = $_[1];
	my $end = $_[2];
	
	if ( $start < 0 ) { $start = 0 }
	$max = @$array[$start];
	for ( $mma = $start; $mma <= $end; $mma++ )
	{
		$val = @$array [ $mma ];
		if ( $max < $val ) { $max = $val; }
	}
	return $max;
}

sub roc () {
	my $array = $_[0];
	my $start = $_[1];
	my $end = $_[2];
	
	if ( $start < 0 ) { $start = 0 }
	
	$first = @$array[$start];
	$last = @$array[$end];

	if ( $first != 0 ) { $roc = $last/$first; }
	else { $roc = 0; }
	
	return $roc;
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
