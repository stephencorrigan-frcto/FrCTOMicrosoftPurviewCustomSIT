$mail = @{ To = 'ops@example.com'; Subject = 'Report'; SmtpServer = 'smtp.local' }
Send-MailMessage @mail -Body $body