tell application "MacLoggerDX"
	set qsoLogMode to system attribute "FLDIGI_MODEM"
	if qsoLogMode starts with "Olivia" then
		set qsoLogMode to "OLIVIA"
	else if qsoLogMode ends with "HELL" then
		set qsoLogMode to "HELL"
	else if qsoLogMode = "BPSK31" then
		set qsoLogMode to "PSK31"
	end if
	
	lookup (system attribute "FLDIGI_LOG_CALL")
	delay 1
	setLogFrequency ((system attribute "FLDIGI_FREQUENCY") / 1000000)
	setLogMode qsoLogMode
	
end tell
