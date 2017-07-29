#!/usr/bin/perl

# Use section
use Date::Calc qw(Today_and_Now);
use Date::Calc qw(Add_Delta_Days);
use File::Copy;
use File::Basename;
use DBI;
use Net::SMTP;
use Net::SMTP::SSL;
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

my @files;
my @fileparts;
my @lines;

my $code;
my $epsyear;

my $eps172;
my $eps171;
my $eps17;
my $eps162;
my $eps161;
my $eps16;
my $eps152;
my $eps151;
my $eps15;
my $eps142;
my $eps141;
my $eps14;

my $eps172g;
my $eps171g;
my $eps17g;
my $eps162g;
my $eps161g;
my $eps16g;
my $eps152g;
my $eps151g;
my $eps15g;
my $eps142g;
my $eps141g;
my $eps14g;


my $filecount = 0;

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

	@files = glob("$htmldir/*-Analysis.html");
	if (! @files)
	{
		$thismessage = "No data files in $datadir";
		logentry ( $thismessage );
		$message .= "$thismessage\n";
		$keepgoing = 0;
	}
}

foreach $datafile (@files)
{
	$filecount++;
	$keepgoing = 1;	
	
	$eps172 = -999;
	$eps171 = -999;
	$eps17 = -999;
	$eps162 = -999;
	$eps161 = -999;
	$eps16 = -999;
	$eps152 = -999;
	$eps151 = -999;
	$eps15 = -999;
	$eps142 = -999;
	$eps141 = -999;
	$eps14 = -999;

	$eps172g = -999;
	$eps171g = -999;
	$eps17g = -999;
	$eps162g = -999;
	$eps161g = -999;
	$eps16g = -999;
	$eps152g = -999;
	$eps151g = -999;
	$eps15g = -999;
	$eps142g = -999;
	$eps141g = -999;
	$eps14g = -999;

	if ( $datafile =~ /$htmldir\/(.*)-Analysis.html/ ) { $code = $1; }

	print	 $code."\n";
	
	open DATA, "<", $datafile or do
	{
		$thismessage = "$0: open $datafile: $!";
		logentry ( $thismessage );
		$message .= "$thismessage\n";
		$keepgoing = 0;
	};
	
	if ( $keepgoing )
	{
		@fileparts = readline (DATA);
		close DATA;
	}

	if (! @fileparts)
	{
		$thismessage = "No data in $datafile data file";
		logentry ( $thismessage );
		$message .= "$thismessage\n";
	}
	foreach $filepart (@fileparts)
	{
		@lines = split ("\\cM", $filepart);
		
		foreach $line (@lines)
		{
			chomp($line);
		
			if ( $line =~ /PeriodEnding.*30\/06\/(.*)\<\/span\>/ ) { $epsyear = $1; }
			if ( $line =~ /PeriodEnding.*30\/12\/(.*)\<\/span\>/ ) { $epsyear = $1; }
			if ( $line =~ /FirstHalf.*\>(.*)\<\/span\>/ )
			{
				$eps = $1;
				$eps =~ s/,//g;
				if ( $eps ne "--" )
				{
					if ( $epsyear == 2017 ) { $eps171 = $eps; }
					if ( $epsyear == 2016 ) { $eps161 = $eps; }
					if ( $epsyear == 2015 ) { $eps151 = $eps; }
					if ( $epsyear == 2014 ) { $eps141 = $eps; }
				}
			}

			if ( $line =~ /SecondHalf.*\>(.*)\<\/span\>/ )
			{
				$eps = $1;
				$eps =~ s/,//g;
				if ( $eps ne "--" )
				{
					if ( $epsyear == 2017 ) { $eps172 = $eps; }
					if ( $epsyear == 2016 ) { $eps162 = $eps; }
					if ( $epsyear == 2015 ) { $eps152 = $eps; }
					if ( $epsyear == 2014 ) { $eps142 = $eps; }
				}
			}

			if ( $line =~ /FullYear.*\>(.*)\<\/span\>/ )
			{
				$eps = $1;
				$eps =~ s/,//g;
				if ( $eps ne "--" )
				{
					if ( $epsyear == 2017 ) { $eps17 = $eps; }
					if ( $epsyear == 2016 ) { $eps16 = $eps; }
					if ( $epsyear == 2015 ) { $eps15 = $eps; }
					if ( $epsyear == 2014 ) { $eps14 = $eps; }
				}
			}
		}
	}

	#calculate growth figures

	$eps172g = growth($eps172, $eps171 );
	$eps171g = growth($eps171, $eps162 );
	$eps162g = growth($eps162, $eps161 );
	$eps161g = growth($eps161, $eps152 );
	$eps152g = growth($eps152, $eps151 );
	$eps151g = growth($eps151, $eps142 );
	$eps142g = growth($eps142, $eps141 );
	
	$eps17g = growth($eps17, $eps16 );
	$eps16g = growth($eps16, $eps15 );
	$eps15g = growth($eps15, $eps14 );
	
	#check if figures record already exists
	$found = 0;
	$sql = "select code from fundamentals WHERE code = '$code'";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	while(@row = $sth->fetchrow_array())
	{
		$found = 1;
	}
	$sth->finish();

	if ( $found )
	{
		$sql = "UPDATE fundamentals SET
				eps171 = '$eps171',
				eps161 = '$eps161',
				eps151 = '$eps151',
				eps141 = '$eps141',
				eps172 = '$eps172',
				eps162 = '$eps162',
				eps152 = '$eps152',
				eps142 = '$eps142',
				eps17 = '$eps17',
				eps16 = '$eps16',
				eps15 = '$eps15',
				eps14 = '$eps14'
			WHERE code = '$code'";
	}
	else
	{
		$sql = "INSERT INTO fundamentals SET
				code = '$code',
				eps171 = '$eps171',
				eps161 = '$eps161',
				eps151 = '$eps151',
				eps141 = '$eps141',
				eps172 = '$eps172',
				eps162 = '$eps162',
				eps152 = '$eps152',
				eps142 = '$eps142',
				eps17 = '$eps17',
				eps16 = '$eps16',
				eps15 = '$eps15',
				eps14 = '$eps14'";
	}
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	if ( ! $result )
	{
		$thismessage = $sth->errstr.":".$sql;
		logentry ( $thismessage );
		$message .= $thismessage."\n";
	}
	$sth->finish();

	#check if growth  record already exists
	$found = 0;
	$sql = "select code from growth WHERE code = '$code'";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	while(@row = $sth->fetchrow_array())
	{
		$found = 1;
	}
	$sth->finish();

	if ( $found )
	{
		$sql = "UPDATE growth SET
				eps171g = '$eps171g',
				eps161g = '$eps161g',
				eps151g = '$eps151g',
				eps141g = '$eps141g',
				eps172g = '$eps172g',
				eps162g = '$eps162g',
				eps152g = '$eps152g',
				eps142g = '$eps142g',
				eps17g = '$eps17g',
				eps16g = '$eps16g',
				eps15g = '$eps15g',
				eps14g = '$eps14g'
			WHERE code = '$code'";
	}
	else
	{
		$sql = "INSERT INTO growth SET
				code = '$code',
				eps171g = '$eps171g',
				eps161g = '$eps161g',
				eps151g = '$eps151g',
				eps141g = '$eps141g',
				eps172g = '$eps172g',
				eps162g = '$eps162g',
				eps152g = '$eps152g',
				eps142g = '$eps142g',
				eps17g = '$eps17g',
				eps16g = '$eps16g',
				eps15g = '$eps15g',
				eps14g = '$eps14g'";
	}
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	if ( ! $result )
	{
		$thismessage = $sth->errstr.":".$sql;
		logentry ( $thismessage );
		$message .= $thismessage."\n";
	}
	$sth->finish();
}
$dbh->disconnect();

$message .= "Loaded Analysis files for $filecount files\n";

# closing
sendreport ( $message );
close LOG;

sub growth () {
	my $now = $_[0];
	my $before = $_[1];
	
	$growth = 0;
	
	if ( $now == -999 or $before == -999 ) { $growth = -999; }
	else
	{
		if ( $before == 0 )
		{
			if ( $now == 0 ) { $growth = 0; }
			if ( $now > 0 ) { $growth = 25; }
			if ( $now < 0 ) { $growth = -25; }
		}
		elsif ( $before <= 0 and $now >=0 ) 		{ $growth = $now - $before / abs($before) ; }
		elsif ( $before <= 0 and $before <= $now ) 	{ $growth = abs($now) - abs($before) / $before ; }
		elsif ( $before >= 0 and $now <=0 )	 	{ $growth = ($now-$before)/$before ; }
		elsif ( $before >= 0 and $now >=0 )	 	{ $growth = ($now-$before)/$before ; }
		elsif ( $before <= 0 and $before <= $now  )	{ $growth = abs($now) - abs($before) / $before ; }
		$growth = $growth * 100;
	}
	return $growth;
}


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

