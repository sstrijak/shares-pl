#!/usr/bin/perl

# Use section
use Date::Calc qw(Today_and_Now);
use File::Copy;
use File::Basename;
use DBI;
use Net::SMTP;
use Net::SMTP::SSL;

# Date run and mypath
($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
my $starttime = "$year-$month-$day-$hour:$min:$sec";
my ($pname, $mypath, $type) = fileparse($0,qr{\..*});

# File and directories
$logfile = "$mypath/$pname.log";
$arcdir = "$mypath/archive";

# SMTP
my $smtpserver = 'mail.7r.com.au';
my $smtpport = 465;
my $smtpuser   = 'shares@7r.com.au';
my $smtppassword = 'D3l3t312';
my $mailfrom = "shares\@7r.com.au";
my $mailto = "sstrijak\@7r.com.au";
my $subject = "$pname on $starttime";
my $otomessage = "";
my $message = "";

# mySQL
my $dbname = "shares";
my $dbhost = "localhost";
my $dbport = 3306;
my $dbuser = "shares";
my $dbpassword = "D3l3t312";
my $dbtable = "daily";

# Flow control and reporting
my $keepgoing = 1;
my $filecount = 0;
my $recordcount = 0;

# Script data
my $stock,$dateymd,$open,$high,$low,$close,$volume;
my @files;

########## Read parameters and display help message
$datadir = "";
if ( defined ( $ARGV[0] ) ) {
	$datadir = $ARGV[0];
}

if ( $datadir eq "" or $datadir eq "?" or $datadir eq "-?" or $datadir eq "-h") {
	print "Usage: perl stocks2db.pl <directory with stock data files *.TXT>\n";
	print "# This script takes stock data from the files in the given directory and loads into the stocks table of the shares database\n";
	exit;
}

########## Read parameters and display help message

open LOG, ">>", $logfile;
logentry ("Loading of stock data from $datadir" ); 


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

if ($keepgoing) {
	@files = glob("$datadir/*.TXT");
	if (! @files)
	{
		@files = glob("$datadir/*.csv");
		if (! @files)
		{
			$thismessage = "No data files in $datadir";
			logentry ( $thismessage );
			$message .= "$thismessage\n";
			$keepgoing = 0;
		}
	}
}

foreach $datafile (@files)
{
	print $datafile."\n";
	$filecount++;
	$keepgoing = 1;	
	@stockdata = ();
	
	open DATA, "<", $datafile or do
	{
		$thismessage = "$0: open $datafile: $!";
		logentry ( $thismessage );
		$message .= "$thismessage\n";
		$keepgoing = 0;
	};
	
	if ( $keepgoing )
	{
		@stockdata = readline (DATA);
		close DATA;
	}

	if (! @stockdata)
	{
		$thismessage = "No data in $datafile data file";
		logentry ( $thismessage );
		$message .= "$thismessage\n";
	}
	
	foreach $stockline (@stockdata)
	{
		if ( $keepgoing and $stockline )
		{

			($stock,$dateymd,$open,$high,$low,$close,$volume) = split ("," , $stockline);
			if ( $dateymd =~ /(.*)\/(.*)\/(.*)/ )
			{
				$day = $1;
				$month = $2;
				$year = $3;
			}
			else
			{
				$year = substr $dateymd, 0, 4;
				$month = substr $dateymd, 4, 2;
				$day = substr $dateymd, 6, 2;
			}
			$sql = "INSERT IGNORE INTO `$dbtable` SET `code` = '$stock',`date` = '$year-$month-$day',`open` = '$open',`high` = '$high',`low` = '$low',`close` = '$close',`volume` = '$volume'";
			$dbh->do( $sql );
			$error = $dbh->{'mysql_error'};

			if ( $error and ! $otomessage )
			{
				$thismessage = "Error inserting to database: $error";
				logentry ( $thismessage );
				$message .= "$thismessage\n";
				$otomessage = $thismessage;
				$keepgoing = 0;
			}
			else
			{
				$recordcount++;
			}
		}
	}
	move($datafile, $arcdir) or do
	{
		$thismessage = "$0: move $datafile => $arcdir: $!";
		logentry ( $thismessage );
		$message .= "$thismessage\n";
		$keepgoing = 0;
	}
}
$dbh->disconnect();

$message .= "$filecount files were processed\n$recordcount records added to the database\n";

#my $updatevolumes = `updatevolumes.pl 1`;

# closing
sendreport ( $message );
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

