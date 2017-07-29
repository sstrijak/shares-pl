#!/usr/bin/perl

# Use section
use Date::Calc qw(Today_and_Now);
use Date::Calc qw( Date_to_Days );
use File::Copy;
use File::Basename;
use DBI;
use Net::SMTP;
use Net::SMTP::SSL;
use LWP::UserAgent;
use HTTP::Request::Common qw{ POST };
use HTTP::Cookies;

# Date run and mypath
($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
my $starttime = "$year-$month-$day-$hour:$min:$sec";
my ($pname, $mypath, $type) = fileparse($0,qr{\..*});

# File and directories
$logfile = "$mypath/$pname.log";
$bufferdir = "$mypath/buffer";
mkdir $bufferdir unless -d $bufferdir;

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

# Cool Trader
my $cooluser = "sstrijak";
my $coolpass = "D3l3t312";

# Flow control and reporting
my $keepgoing = 1;

# Script data
my $lastdate;
my $lastyear;
my $lastmonth;
my $lastday;
my $ua;
my $cookie_jar;
my $daycount = 0;

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
	# Check what is last date in the database
	$lastdate = "";
	$sql = "select date from $dbtable where code='XAO' order by date desc limit 1";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	while(@row = $sth->fetchrow_array())
	{
		$lastdate = $row[0];
		( $lastyear, $lastmonth, $lastday ) = split ('-', $lastdate );
	}

	if ( ! $lastdate ) {
		$thismessage = "Failed to get last date in the stocks table";
		logentry ( $thismessage );
		$message .= "$thismessage\n";
		$keepgoing = 0;
	}
}

if ($keepgoing)
{
	$coollogin_url = "http://www.cooltrader.com.au/amember/login.php";
	$cooldownlist_url = "http://www.cooltrader.com.au/members/1030/downloadcsv.php";

	$ua = LWP::UserAgent->new;
	$cookie_jar = HTTP::Cookies->new;

	my $request = POST( $coollogin_url, [
		'amember_login' => $cooluser,
		'amember_pass' => $coolpass,
	] );

	$response = $ua->request( $request );
	$cookie_jar->extract_cookies( $response );
	$ua->cookie_jar( $cookie_jar );

	$response = $ua->get($cooldownlist_url);
	$content = $response->content();
	
	if ( $content )
	{
		@contentlines = split ('\n', $content);
		foreach $line ( @contentlines )
		{
			if ( $line =~ /file=(.*)\.csv\"\>/ )
			{
				$thisdate = $1;
				$thisyear = substr $thisdate, 0, 4;
				$thismonth = substr $thisdate, 4, 2;
				$thisday = substr $thisdate, 6, 2;
				if (	Date_to_Days($thisyear,$thismonth,$thisday)	>
      					Date_to_Days($lastyear,$lastmonth,$lastday)	)
      				{
      					# OK, we dont have this date yet, lets get the file down
      					$cooldownfile_url = "http://www.cooltrader.com.au/members/1030/downloadcsv.php?go=download&path=&file=$thisdate.csv";
					$response = $ua->get($cooldownfile_url);
					$content = $response->content();
					open OUT, ">", "$bufferdir/$thisdate.csv";
					print OUT $content;
					close OUT;
					$daycount++;
      				}
			}
		}
	}
}

`perl stocks2db.pl $bufferdir`;
#`perl updatevolumes.pl $daycount`;
#`perl averages.pl`;

# closing
# sendreport ( "Completed" );
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

