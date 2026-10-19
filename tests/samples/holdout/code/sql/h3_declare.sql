DECLARE @Cutoff DATE = DATEADD(day, -30, GETDATE());
DELETE FROM dbo.AuditLog WHERE LoggedAt < @Cutoff;