tell application "MacLoggerDX"
	setRSTS (system attribute "FLDIGI_LOG_RST_OUT")
	setRSTR (system attribute "FLDIGI_LOG_RST_IN")
	setNOTE (system attribute "FLDIGI_LOG_NOTES")
	log
end tell
