<#
.SYNOPSIS
  Windows front end for deploying the code SITs and DLP policies to a Microsoft 365 tenant.

.DESCRIPTION
  Double-click Deploy.cmd in the repo root (or run this script). The window walks through:
    1. Sign in      Microsoft's own sign-in window (username, password, MFA). This tool never sees the password.
    2. Choose       SIT packs, the AI desktop app group, policy names, alert recipients, mode and confidence.
    3. Preview      Shows exactly what would change in the tenant. Nothing changes.
    4. Deploy       Confirms the tenant, then runs scripts\Invoke-CodeSitDeployment.ps1 -Apply.

  Settings can be saved per customer (profiles\, git-ignored) and loaded next time. Every deployment writes a
  backup of the tenant's custom SITs and app groups plus the run log to exports\<domain>-<time>\.

  Needs Windows, Windows PowerShell 5.1 or PowerShell 7, and the ExchangeOnlineManagement module (the window
  offers to install it for the current user). The account needs Compliance Administrator or equivalent.
#>
param()
$ErrorActionPreference = 'Stop'

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    # WPF needs a single-threaded apartment; relaunch in Windows PowerShell with -STA
    Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$PSCommandPath`""
    return
}
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Netrio Code DLP Deployer" Width="1120" Height="820" MinWidth="960" MinHeight="680"
        WindowStartupLocation="CenterScreen" Background="#E8EEF2"
        FontFamily="Open Sans, Arial" FontSize="13" Foreground="#383F42">
  <Window.Resources>
    <SolidColorBrush x:Key="Charcoal" Color="#383F42"/>
    <SolidColorBrush x:Key="Teal" Color="#009A9A"/>
    <SolidColorBrush x:Key="Yellow" Color="#FBB033"/>
    <SolidColorBrush x:Key="Red" Color="#EE3124"/>
    <SolidColorBrush x:Key="Mist" Color="#E8EEF2"/>
    <SolidColorBrush x:Key="Muted" Color="#5E676B"/>
    <SolidColorBrush x:Key="Line" Color="#CBD5DC"/>
    <LinearGradientBrush x:Key="Burst" StartPoint="0,0" EndPoint="1,0">
      <GradientStop Color="#EE3124" Offset="0"/>
      <GradientStop Color="#FBB034" Offset="1"/>
    </LinearGradientBrush>
    <LinearGradientBrush x:Key="TealGrad" StartPoint="0,0" EndPoint="1,1">
      <GradientStop Color="#009A9A" Offset="0.55"/>
      <GradientStop Color="#383F42" Offset="1"/>
    </LinearGradientBrush>

    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Background" Value="{StaticResource Teal}"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="FontFamily" Value="Inter SemiBold, Inter, Arial"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="18,8"/>
      <Setter Property="Margin" Value="8,0,0,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="bd" Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="BtnGhost" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="White"/>
      <Setter Property="Foreground" Value="{StaticResource Charcoal}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
    </Style>
    <Style x:Key="BtnBurst" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="{StaticResource Burst}"/>
    </Style>

    <Style TargetType="TextBox">
      <Setter Property="Padding" Value="6,5"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="Margin" Value="0,4,0,10"/>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Padding" Value="6,5"/>
      <Setter Property="Margin" Value="0,4,0,10"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Margin" Value="0,4,0,6"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
    <Style x:Key="Label" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Inter SemiBold, Inter, Arial"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="12"/>
    </Style>
    <Style x:Key="Hint" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="Margin" Value="0,0,0,8"/>
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="White"/>
      <Setter Property="CornerRadius" Value="6"/>
      <Setter Property="Padding" Value="18,14"/>
      <Setter Property="Margin" Value="0,0,0,12"/>
    </Style>
    <Style x:Key="Num" TargetType="Border">
      <Setter Property="Width" Value="26"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="CornerRadius" Value="13"/>
      <Setter Property="Background" Value="{StaticResource TealGrad}"/>
      <Setter Property="Margin" Value="0,0,10,0"/>
    </Style>
    <Style x:Key="NumText" TargetType="TextBlock">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontFamily" Value="Inter Black, Arial Black"/>
      <Setter Property="FontWeight" Value="Black"/>
      <Setter Property="HorizontalAlignment" Value="Center"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style x:Key="CardTitle" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Inter SemiBold, Inter, Arial"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="16"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="6"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- header -->
    <Border Grid.Row="0" Background="White" Padding="24,14">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Image x:Name="Logo" Height="46" Margin="0,0,22,0" RenderOptions.BitmapScalingMode="HighQuality"/>
        <StackPanel Grid.Column="1" VerticalAlignment="Center">
          <TextBlock Text="Code DLP Deployer" FontFamily="Inter Black, Arial Black" FontWeight="Black" FontSize="22"/>
          <TextBlock Text="Source code detection and data loss prevention (DLP) for Microsoft Purview" Foreground="{StaticResource Muted}"/>
        </StackPanel>
        <Border Grid.Column="2" x:Name="TenantChip" Background="{StaticResource Mist}" CornerRadius="14" Padding="14,6" VerticalAlignment="Center">
          <StackPanel Orientation="Horizontal">
            <Ellipse x:Name="TenantDot" Width="9" Height="9" Fill="{StaticResource Line}" Margin="0,0,8,0" VerticalAlignment="Center"/>
            <TextBlock x:Name="TenantChipText" Text="Not signed in" Style="{StaticResource Label}" VerticalAlignment="Center"/>
          </StackPanel>
        </Border>
      </Grid>
    </Border>
    <Border Grid.Row="1" Background="{StaticResource Burst}"/>

    <!-- body -->
    <Grid Grid.Row="2" Margin="20,16,20,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="500"/>
        <ColumnDefinition Width="16"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto">
        <StackPanel>

          <!-- 1 sign in -->
          <Border Style="{StaticResource Card}">
            <StackPanel>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                <Border Style="{StaticResource Num}"><TextBlock Text="1" Style="{StaticResource NumText}"/></Border>
                <TextBlock Text="Sign in to the customer tenant" Style="{StaticResource CardTitle}"/>
              </StackPanel>
              <TextBlock Style="{StaticResource Hint}" Text="Microsoft's sign-in window asks for the admin's username, password and MFA. The password goes to Microsoft only; this tool never sees it. The account needs Compliance Administrator (or a role that manages DLP)."/>
              <Grid x:Name="ModulePanel" Visibility="Collapsed" Margin="0,0,0,10">
                <Border Background="#FFF6E5" BorderBrush="{StaticResource Yellow}" BorderThickness="1" CornerRadius="4" Padding="10,8">
                  <Grid>
                    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                    <TextBlock TextWrapping="Wrap" VerticalAlignment="Center" Text="The ExchangeOnlineManagement PowerShell module is needed and is not installed."/>
                    <Button x:Name="InstallBtn" Grid.Column="1" Content="Install module" Style="{StaticResource BtnGhost}" Padding="12,6"/>
                  </Grid>
                </Border>
              </Grid>
              <TextBlock Text="Admin username (optional)" Style="{StaticResource Label}"/>
              <TextBox x:Name="AdminUpn" ToolTip="Pre-fills the Microsoft sign-in window, for example admin@customer.com. Leave blank to type it there."/>
              <StackPanel Orientation="Horizontal">
                <Button x:Name="SignInBtn" Content="Sign in" Style="{StaticResource Btn}" Margin="0"/>
                <Button x:Name="SignOutBtn" Content="Sign out" Style="{StaticResource BtnGhost}" IsEnabled="False"/>
                <TextBlock x:Name="SignInStatus" Text="Not signed in" VerticalAlignment="Center" Margin="14,0,0,0" Foreground="{StaticResource Muted}" TextWrapping="Wrap" MaxWidth="240"/>
              </StackPanel>
            </StackPanel>
          </Border>

          <!-- 2 SITs -->
          <Border Style="{StaticResource Card}">
            <StackPanel>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                <Border Style="{StaticResource Num}"><TextBlock Text="2" Style="{StaticResource NumText}"/></Border>
                <TextBlock Text="Detection rules (custom SITs)" Style="{StaticResource CardTitle}"/>
              </StackPanel>
              <CheckBox IsChecked="True" IsEnabled="False" Content="Stable pack: Python, SQL, Java, JavaScript/TypeScript, multi-language"/>
              <CheckBox x:Name="IncludeExperimental" Content="Also the experimental pack: C#, PowerShell, C/C++, Go, Bash, structural"/>
              <TextBlock Style="{StaticResource Hint}" Text="Experimental SITs catch more languages but are less tested (see docs\TESTING.md). When ticked they are imported and used in the policies."/>
            </StackPanel>
          </Border>

          <!-- 3 app group -->
          <Border Style="{StaticResource Card}">
            <StackPanel>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                <Border Style="{StaticResource Num}"><TextBlock Text="3" Style="{StaticResource NumText}"/></Border>
                <TextBlock Text="AI desktop apps (Endpoint DLP)" Style="{StaticResource CardTitle}"/>
              </StackPanel>
              <CheckBox x:Name="AppGroupOn" IsChecked="True" Content="Create or update a restricted app group"/>
              <StackPanel x:Name="AppGroupPanel">
                <TextBlock Text="Group name" Style="{StaticResource Label}" Margin="0,6,0,0"/>
                <TextBox x:Name="AppGroupName" Text="AI desktop apps"/>
                <TextBlock Text="Apps, one per line: Display name = executable" Style="{StaticResource Label}"/>
                <TextBox x:Name="Apps" AcceptsReturn="True" Height="70" VerticalScrollBarVisibility="Auto" FontFamily="Consolas" Text="Claude Desktop = claude.exe"/>
                <TextBlock Style="{StaticResource Hint}" Text="Existing groups and apps are kept and backed up. Check each executable name on a device (Task Manager, Details tab): a wrong name silently matches nothing."/>
              </StackPanel>
            </StackPanel>
          </Border>

          <!-- 4 policies -->
          <Border Style="{StaticResource Card}">
            <StackPanel>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                <Border Style="{StaticResource Num}"><TextBlock Text="4" Style="{StaticResource NumText}"/></Border>
                <TextBlock Text="DLP policies" Style="{StaticResource CardTitle}"/>
              </StackPanel>
              <TextBlock Text="Alert recipients" Style="{StaticResource Label}"/>
              <TextBox x:Name="AlertRecipients" ToolTip="Email addresses that receive DLP alerts, separated by commas or semicolons."/>
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <StackPanel>
                  <TextBlock Text="Policy name prefix" Style="{StaticResource Label}"/>
                  <TextBox x:Name="Prefix" Text="Code DLP"/>
                </StackPanel>
                <StackPanel Grid.Column="2">
                  <TextBlock Text="Confidence" Style="{StaticResource Label}"/>
                  <ComboBox x:Name="Confidence" SelectedIndex="0">
                    <ComboBoxItem Content="High (fewer alerts)" Tag="High"/>
                    <ComboBoxItem Content="Medium (catches short snippets)" Tag="Medium"/>
                  </ComboBox>
                </StackPanel>
              </Grid>
              <TextBlock Text="Policy mode" Style="{StaticResource Label}"/>
              <ComboBox x:Name="Mode" SelectedIndex="0">
                <ComboBoxItem Content="Simulation, no user notifications (recommended)" Tag="TestWithoutNotifications"/>
                <ComboBoxItem Content="Simulation, with user notifications" Tag="TestWithNotifications"/>
                <ComboBoxItem Content="On (enforced; actions are still audit only)" Tag="Enable"/>
                <ComboBoxItem Content="Off" Tag="Disable"/>
              </ComboBox>
              <CheckBox x:Name="Classifier" Content="Add Microsoft's built-in Source code classifier"/>
              <CheckBox x:Name="AttachmentAudit" Content="Log every external email with an attachment (separate policy)"/>
              <TextBlock Style="{StaticResource Hint}" Margin="0,6,0,0" Text="Nothing is blocked: every action is audit. Existing policies with the same name are skipped, never changed."/>
            </StackPanel>
          </Border>
        </StackPanel>
      </ScrollViewer>

      <!-- log -->
      <Border Grid.Column="2" Background="{StaticResource Charcoal}" CornerRadius="6" Margin="0,0,0,12">
        <Grid>
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <Grid Margin="16,12,12,6">
            <TextBlock Text="Activity" Foreground="White" FontFamily="Inter SemiBold, Inter, Arial" FontWeight="SemiBold" FontSize="15" VerticalAlignment="Center"/>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
              <Button x:Name="ClearLogBtn" Content="Clear" Style="{StaticResource BtnGhost}" Padding="10,4" Background="Transparent" Foreground="White" BorderBrush="#5E676B"/>
              <Button x:Name="SaveLogBtn" Content="Save log" Style="{StaticResource BtnGhost}" Padding="10,4" Background="Transparent" Foreground="White" BorderBrush="#5E676B"/>
            </StackPanel>
          </Grid>
          <TextBox x:Name="Log" Grid.Row="1" IsReadOnly="True" Background="Transparent" Foreground="#E8EEF2" BorderThickness="0"
                   FontFamily="Consolas" FontSize="12" Margin="10,0,6,10" TextWrapping="NoWrap"
                   VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
        </Grid>
      </Border>
    </Grid>

    <!-- footer -->
    <Border Grid.Row="3" Background="White" Padding="20,12" BorderBrush="{StaticResource Line}" BorderThickness="0,1,0,0">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <ProgressBar x:Name="Busy" Width="90" Height="5" IsIndeterminate="True" Visibility="Collapsed" Margin="0,0,12,0" Foreground="{StaticResource Teal}" Background="{StaticResource Mist}" BorderThickness="0"/>
          <TextBlock x:Name="Status" Text="Sign in to begin." Foreground="{StaticResource Muted}" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button x:Name="LoadBtn" Content="Load settings" Style="{StaticResource BtnGhost}"/>
          <Button x:Name="SaveBtn" Content="Save settings" Style="{StaticResource BtnGhost}"/>
          <Button x:Name="PreviewBtn" Content="Preview changes" Style="{StaticResource Btn}" Margin="20,0,0,0"/>
          <Button x:Name="DeployBtn" Content="Deploy" Style="{StaticResource BtnBurst}" Padding="26,8"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
foreach ($n in $xaml.SelectNodes('//*[@*[local-name()="Name"]]')) {
    $name = $n.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
    $el = $win.FindName($name); if ($el) { $ui[$name] = $el }
}
function New-Bitmap([string]$path) {
    $b = New-Object Windows.Media.Imaging.BitmapImage
    $b.BeginInit(); $b.UriSource = [Uri]$path; $b.CacheOption = 'OnLoad'; $b.EndInit(); $b.Freeze(); $b
}
$ui.Logo.Source = New-Bitmap (Join-Path $root 'assets\netrio-logo.png')
$win.Icon = New-Bitmap (Join-Path $root 'assets\netrio-icon.png')

# ---------- worker: one background runspace keeps the sign-in session for every task ----------
$iss = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
try { $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass } catch { }
$rs = [runspacefactory]::CreateRunspace($iss)
$rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
$script:job = $null
$script:signedIn = $null
$script:previewKey = $null
$script:logLines = New-Object System.Collections.Generic.List[string]

# Every task: param($P), body output and all streams become log lines; $JobFailed marks a terminating error.
$jobTemplate = @'
param($P)
$global:JobFailed = $false
try {
    & { BODY } *>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) { "ERROR: $_" }
        elseif ($_ -is [System.Management.Automation.WarningRecord]) { "WARNING: $($_.Message)" }
        elseif ($_ -is [System.Management.Automation.InformationRecord]) { [string]$_.MessageData }
        elseif ($_ -is [System.Management.Automation.VerboseRecord] -or $_ -is [System.Management.Automation.DebugRecord] -or $_ -is [System.Management.Automation.ProgressRecord]) { }
        else { $_ }
    } | Out-String -Stream -Width 200
}
catch { "ERROR: $($_.Exception.Message)"; $global:JobFailed = $true }
'@

function Write-Log([string]$text) {
    foreach ($line in ($text -split "`r?`n")) { $script:logLines.Add($line); $ui.Log.AppendText($line + "`r`n") }
    $ui.Log.ScrollToEnd()
}
function Set-Busy([bool]$busy, [string]$text) {
    $ui.Busy.Visibility = if ($busy) { 'Visible' } else { 'Collapsed' }
    if ($text) { $ui.Status.Text = $text }
    $ui.SignInBtn.IsEnabled = -not $busy
    $ui.SignOutBtn.IsEnabled = (-not $busy) -and [bool]$script:signedIn
    $ui.InstallBtn.IsEnabled = -not $busy
    $ui.PreviewBtn.IsEnabled = -not $busy
    $ui.DeployBtn.IsEnabled = -not $busy
    $ui.LoadBtn.IsEnabled = -not $busy
}
# OnDone runs on the UI thread as: & $OnDone $failed $Ctx
function Start-Work([string]$Title, [string]$Body, [hashtable]$P, [scriptblock]$OnDone, [hashtable]$Ctx = @{}) {
    if ($script:job) { return }
    Write-Log ''; Write-Log ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $Title)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($jobTemplate.Replace('BODY', $Body)).AddParameter('P', $P)
    $in = New-Object 'System.Management.Automation.PSDataCollection[psobject]'; $in.Complete()
    $out = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
    $script:job = @{ PS = $ps; Out = $out; Read = 0; OnDone = $OnDone; Ctx = $Ctx; Handle = $ps.BeginInvoke($in, $out) }
    Set-Busy $true "$Title..."
}
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(150)
$timer.Add_Tick({
    $j = $script:job; if (-not $j) { return }
    while ($j.Read -lt $j.Out.Count) { Write-Log ([string]$j.Out[$j.Read]); $j.Read++ }
    if (-not $j.Handle.IsCompleted) { return }
    $failed = $false
    try { [void]$j.PS.EndInvoke($j.Handle) } catch { Write-Log "ERROR: $($_.Exception.GetBaseException().Message)"; $failed = $true }
    while ($j.Read -lt $j.Out.Count) { Write-Log ([string]$j.Out[$j.Read]); $j.Read++ }
    foreach ($e in $j.PS.Streams.Error) { Write-Log "ERROR: $e" }
    if ($rs.SessionStateProxy.GetVariable('JobFailed')) { $failed = $true }
    $j.PS.Dispose(); $script:job = $null
    Set-Busy $false
    & $j.OnDone $failed $j.Ctx
})
$timer.Start()

# ---------- settings ----------
function Get-Settings {
    [ordered]@{
        AdminUpn            = $ui.AdminUpn.Text.Trim()
        IncludeExperimental = [bool]$ui.IncludeExperimental.IsChecked
        AppGroup            = [bool]$ui.AppGroupOn.IsChecked
        AppGroupName        = $ui.AppGroupName.Text.Trim()
        Apps                = $ui.Apps.Text.Trim()
        AlertRecipients     = $ui.AlertRecipients.Text.Trim()
        Prefix              = $ui.Prefix.Text.Trim()
        Confidence          = [string]$ui.Confidence.SelectedItem.Tag
        Mode                = [string]$ui.Mode.SelectedItem.Tag
        SourceCodeClassifier = [bool]$ui.Classifier.IsChecked
        AttachmentAudit     = [bool]$ui.AttachmentAudit.IsChecked
    }
}
function Set-Settings($s) {
    if ($null -ne $s.AdminUpn) { $ui.AdminUpn.Text = $s.AdminUpn }
    if ($null -ne $s.IncludeExperimental) { $ui.IncludeExperimental.IsChecked = [bool]$s.IncludeExperimental }
    if ($null -ne $s.AppGroup) { $ui.AppGroupOn.IsChecked = [bool]$s.AppGroup }
    if ($s.AppGroupName) { $ui.AppGroupName.Text = $s.AppGroupName }
    if ($null -ne $s.Apps) { $ui.Apps.Text = $s.Apps }
    if ($null -ne $s.AlertRecipients) { $ui.AlertRecipients.Text = $s.AlertRecipients }
    if ($s.Prefix) { $ui.Prefix.Text = $s.Prefix }
    foreach ($pair in @(@($ui.Confidence, $s.Confidence), @($ui.Mode, $s.Mode))) {
        $item = $pair[0].Items | Where-Object { $_.Tag -eq $pair[1] } | Select-Object -First 1
        if ($item) { $pair[0].SelectedItem = $item }
    }
    if ($null -ne $s.SourceCodeClassifier) { $ui.Classifier.IsChecked = [bool]$s.SourceCodeClassifier }
    if ($null -ne $s.AttachmentAudit) { $ui.AttachmentAudit.IsChecked = [bool]$s.AttachmentAudit }
}

# Validates the form; returns the parameters for Invoke-CodeSitDeployment.ps1, or $null after showing the problems.
function Get-RunArgs {
    $s = Get-Settings; $problems = @()
    $recips = @($s.AlertRecipients -split '[,;\s]+' | Where-Object { $_ })
    if (-not $recips) { $problems += 'Enter at least one alert recipient.' }
    foreach ($r in $recips) { if ($r -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { $problems += "Not an email address: $r" } }
    if (-not $s.Prefix) { $problems += 'Enter a policy name prefix.' }
    elseif ($s.Prefix.Length -gt 40) { $problems += 'Keep the policy name prefix to 40 characters or fewer.' }
    $apps = @()
    if ($s.AppGroup) {
        if (-not $s.AppGroupName) { $problems += 'Enter a name for the app group.' }
        foreach ($line in ($s.Apps -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
            $parts = $line -split '=', 2
            $exe = $parts[-1].Trim(); $name = if ($parts.Count -eq 2) { $parts[0].Trim() } else { $exe }
            if (-not $exe -or $exe -match '[\\/:*?"<>|]') { $problems += "Not a valid executable name: $line" } else { $apps += @{ Name = $name; ExecutableName = $exe } }
        }
        if (-not $apps) { $problems += 'Add at least one app, or untick the app group.' }
    }
    if ($problems) {
        [void][Windows.MessageBox]::Show($win, ($problems -join "`n"), 'Check the settings', 'OK', 'Warning'); return $null
    }
    $a = @{ SkipConnect = $true; AlertRecipients = $recips; Prefix = $s.Prefix; Mode = $s.Mode; Confidence = $s.Confidence
            IncludeExperimental = $s.IncludeExperimental; IncludeSourceCodeClassifier = $s.SourceCodeClassifier
            IncludeAttachmentAudit = $s.AttachmentAudit; SkipAppGroup = -not $s.AppGroup }
    if ($s.AppGroup) { $a.AppGroupName = $s.AppGroupName; $a.Apps = $apps }
    return $a
}
function Get-PreviewKey {
    $s = Get-Settings; $s.Remove('AdminUpn')
    "$($script:signedIn.TenantId)|" + ($s | ConvertTo-Json -Compress)
}
function Get-TenantTag {
    $d = if ($script:signedIn.Upn) { ($script:signedIn.Upn -split '@')[-1] } else { 'tenant' }
    $d -replace '[^\w.-]', '_'
}

# ---------- sign in / out ----------
function Update-SignIn {
    if ($script:signedIn) {
        $t = "$($script:signedIn.Upn)"
        if ($script:signedIn.TenantId) { $t += "`ntenant $($script:signedIn.TenantId)" }
        $ui.SignInStatus.Text = $t
        $ui.TenantChipText.Text = Get-TenantTag
        $ui.TenantDot.Fill = if ($script:signedIn.CanDlp) { $win.Resources['Teal'] } else { $win.Resources['Red'] }
        $ui.SignInBtn.Content = 'Switch tenant'
        $ui.Status.Text = if ($script:signedIn.CanDlp) { 'Signed in. Check the settings, then Preview changes.' } else { 'Signed in, but this account cannot manage DLP.' }
    } else {
        $ui.SignInStatus.Text = 'Not signed in'; $ui.TenantChipText.Text = 'Not signed in'
        $ui.TenantDot.Fill = $win.Resources['Line']; $ui.SignInBtn.Content = 'Sign in'
        $ui.Status.Text = 'Sign in to begin.'
    }
    $ui.SignOutBtn.IsEnabled = [bool]$script:signedIn
}
function Test-Module {
    $ok = [bool](Get-Module -ListAvailable ExchangeOnlineManagement)
    $ui.ModulePanel.Visibility = if ($ok) { 'Collapsed' } else { 'Visible' }
    return $ok
}

$signInBody = @'
Import-Module ExchangeOnlineManagement
if (Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue) {
    if (Get-ConnectionInformation -ErrorAction SilentlyContinue) { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue }
}
$global:SignedIn = $null
$c = @{ ShowBanner = $false }; if ($P.Upn) { $c.UserPrincipalName = $P.Upn }
'Opening the Microsoft sign-in window (it may appear behind this one)...'
try { Connect-IPPSSession @c -ErrorAction Stop }
catch {
    # the Windows sign-in broker (WAM) can fail in some hosts; retry with the browser sign-in when available
    if ($_.Exception.Message -match 'window handle|WAM|broker' -and (Get-Command Connect-IPPSSession).Parameters.ContainsKey('DisableWAM')) {
        "Sign-in broker failed ($($_.Exception.Message.Split("`n")[0])). Retrying with the browser sign-in..."
        Connect-IPPSSession @c -DisableWAM -ErrorAction Stop
    } else { throw }
}
$ci = $null
if (Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue) { $ci = @(Get-ConnectionInformation | Where-Object { $_.State -eq 'Connected' }) | Select-Object -Last 1 }
$canDlp = [bool](Get-Command Get-DlpCompliancePolicy -ErrorAction SilentlyContinue)
$global:SignedIn = [pscustomobject]@{ Upn = $(if ($ci) { $ci.UserPrincipalName } else { $P.Upn }); TenantId = $(if ($ci) { [string]$ci.TenantID } else { '' }); CanDlp = $canDlp }
"Signed in as $($global:SignedIn.Upn)" + $(if ($global:SignedIn.TenantId) { ", tenant ID $($global:SignedIn.TenantId)" } else { '' })
if (-not $canDlp) { 'WARNING: this account cannot manage DLP in this tenant. It needs Compliance Administrator (or a role group that manages DLP policies and sensitive info types).' }
'@

$ui.SignInBtn.Add_Click({
    if (-not (Test-Module)) { [void][Windows.MessageBox]::Show($win, 'Install the ExchangeOnlineManagement module first (button above).', 'Module needed', 'OK', 'Information'); return }
    $script:previewKey = $null
    Start-Work 'Sign in' $signInBody @{ Upn = $ui.AdminUpn.Text.Trim() } {
        param($failed)
        $script:signedIn = $rs.SessionStateProxy.GetVariable('SignedIn')
        if ($failed -or -not $script:signedIn) { $script:signedIn = $null; Write-Log 'Sign-in did not complete.' }
        Update-SignIn
    }
})
$ui.SignOutBtn.Add_Click({
    Start-Work 'Sign out' 'Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue; "Signed out."' @{} {
        param($failed) $script:signedIn = $null; $script:previewKey = $null; Update-SignIn
    }
})
$ui.InstallBtn.Add_Click({
    $body = @'
"Installing ExchangeOnlineManagement for the current user from the PowerShell Gallery..."
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null }
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber
"Installed."
'@
    Start-Work 'Install ExchangeOnlineManagement' $body @{} { param($failed) if (Test-Module) { $ui.Status.Text = 'Module installed. Sign in to begin.' } }
})

# ---------- preview / deploy ----------
$runBody = '$a = $P.Args; & (Join-Path $P.Root ''scripts\Invoke-CodeSitDeployment.ps1'') @a'

function Test-Ready {
    if (-not $script:signedIn) { [void][Windows.MessageBox]::Show($win, 'Sign in to the customer tenant first.', 'Not signed in', 'OK', 'Information'); return $false }
    if (-not $script:signedIn.CanDlp) { [void][Windows.MessageBox]::Show($win, "$($script:signedIn.Upn) cannot manage DLP in this tenant. Sign in with a Compliance Administrator account.", 'Missing role', 'OK', 'Warning'); return $false }
    return $true
}
$ui.PreviewBtn.Add_Click({
    if (-not (Test-Ready)) { return }
    $a = Get-RunArgs; if (-not $a) { return }
    $key = Get-PreviewKey
    Start-Work "Preview for $(Get-TenantTag)" $runBody @{ Root = $root; Args = $a } {
        param($failed, $ctx)
        if ($failed) { $script:previewKey = $null; $ui.Status.Text = 'Preview found a problem. See the Activity log.' }
        else { $script:previewKey = $ctx.Key; $ui.Status.Text = 'Preview complete. Review the Activity log, then Deploy.' }
    } @{ Key = $key }
})
$ui.DeployBtn.Add_Click({
    if (-not (Test-Ready)) { return }
    $a = Get-RunArgs; if (-not $a) { return }
    if ($script:previewKey -ne (Get-PreviewKey)) {
        [void][Windows.MessageBox]::Show($win, 'Run Preview changes first. Deploy uses exactly the settings you last previewed, for this tenant.', 'Preview first', 'OK', 'Information'); return
    }
    $s = Get-Settings
    $modeText = [string]$ui.Mode.SelectedItem.Content
    $lines = @(
        "Tenant:  $(Get-TenantTag)" + $(if ($script:signedIn.TenantId) { "  ($($script:signedIn.TenantId))" } else { '' })
        "Account: $($script:signedIn.Upn)"
        ''
        'This will:'
        '  - back up the custom SITs already in the tenant'
        '  - import the stable SIT pack' + $(if ($s.IncludeExperimental) { ' and the experimental pack' } else { '' })
    )
    if ($s.AppGroup) { $lines += "  - create or update the app group '$($s.AppGroupName)' (backup first)" }
    $lines += "  - create the '$($s.Prefix) - ...' DLP policies: $modeText"
    $lines += ''; $lines += 'All policy actions are audit only. Deploy now?'
    if ([Windows.MessageBox]::Show($win, ($lines -join "`n"), 'Confirm deployment', 'YesNo', 'Question', 'No') -ne 'Yes') { return }

    $runDir = Join-Path $root ('exports\' + (Get-TenantTag) + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $a.Apply = $true; $a.Force = $true; $a.RunDir = $runDir
    Start-Work "Deploy to $(Get-TenantTag)" $runBody @{ Root = $root; Args = $a } {
        param($failed, $ctx)
        $runDir = $ctx.RunDir; $logStart = $ctx.LogStart
        try {
            New-Item -ItemType Directory -Force $runDir | Out-Null
            $logFile = Join-Path $runDir 'deploy.log'
            [IO.File]::WriteAllLines($logFile, $script:logLines.GetRange($logStart, $script:logLines.Count - $logStart))
            Write-Log "Log saved: $logFile"
        } catch { Write-Log "Could not save the log: $($_.Exception.Message)" }
        $script:previewKey = $null
        if ($failed) {
            $ui.Status.Text = 'Deployment finished with errors. See the Activity log.'
            [void][Windows.MessageBox]::Show($win, "One or more steps failed. Later steps were skipped.`n`nThe log and backups are in:`n$runDir", 'Deployment incomplete', 'OK', 'Warning')
        } else {
            $ui.Status.Text = 'Deployed. Next: portal steps in docs\SETUP.md (step 8).'
            [void][Windows.MessageBox]::Show($win, "Deployment complete.`n`nNext: the portal steps in docs\SETUP.md (step 8), then the field tests (step 9). Policies take about an hour to reach devices.`n`nLog and backups:`n$runDir", 'Deployed', 'OK', 'Information')
        }
    } @{ RunDir = $runDir; LogStart = $script:logLines.Count }
})

# ---------- misc ----------
$ui.AppGroupOn.Add_Click({ $ui.AppGroupPanel.IsEnabled = [bool]$ui.AppGroupOn.IsChecked })
$ui.ClearLogBtn.Add_Click({ $ui.Log.Clear(); $script:logLines.Clear() })
$profileDir = Join-Path $root 'profiles'
$ui.SaveBtn.Add_Click({
    New-Item -ItemType Directory -Force $profileDir | Out-Null
    $d = New-Object Microsoft.Win32.SaveFileDialog
    $d.InitialDirectory = $profileDir; $d.Filter = 'Deployer settings (*.json)|*.json'
    $d.FileName = $(if ($script:signedIn) { Get-TenantTag } else { 'customer' }) + '.json'
    if ($d.ShowDialog($win)) {
        [IO.File]::WriteAllText($d.FileName, ((Get-Settings) | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
        $ui.Status.Text = "Settings saved: $([IO.Path]::GetFileName($d.FileName))"
    }
})
$ui.LoadBtn.Add_Click({
    $d = New-Object Microsoft.Win32.OpenFileDialog
    $d.InitialDirectory = $(if (Test-Path $profileDir) { $profileDir } else { $root }); $d.Filter = 'Deployer settings (*.json)|*.json'
    if ($d.ShowDialog($win)) {
        try { Set-Settings (Get-Content $d.FileName -Raw | ConvertFrom-Json); $ui.AppGroupPanel.IsEnabled = [bool]$ui.AppGroupOn.IsChecked; $ui.Status.Text = "Settings loaded: $([IO.Path]::GetFileName($d.FileName))" }
        catch { [void][Windows.MessageBox]::Show($win, "Could not read $($d.FileName): $($_.Exception.Message)", 'Load settings', 'OK', 'Warning') }
    }
})
$ui.SaveLogBtn.Add_Click({
    $d = New-Object Microsoft.Win32.SaveFileDialog
    $d.Filter = 'Log (*.log)|*.log|Text (*.txt)|*.txt'; $d.FileName = 'deployer-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log'
    if ($d.ShowDialog($win)) { [IO.File]::WriteAllLines($d.FileName, $script:logLines) }
})

$win.Add_Loaded({
    Write-Log 'Netrio Code DLP Deployer'
    Write-Log "Repository: $root"
    if (Test-Module) { Write-Log "ExchangeOnlineManagement $((Get-Module -ListAvailable ExchangeOnlineManagement | Sort-Object Version -Descending | Select-Object -First 1).Version) found." }
    else { Write-Log 'ExchangeOnlineManagement is not installed. Use Install module.' }
    Update-SignIn
    $win.Activate() | Out-Null
})
$win.Add_Closing({
    param($sender, $e)
    if ($script:job) {
        if ([Windows.MessageBox]::Show($win, 'A task is still running. Close anyway?', 'Close', 'YesNo', 'Warning', 'No') -ne 'Yes') { $e.Cancel = $true; return }
        $script:forceExit = $true
        return
    }
    $timer.Stop()
    if ($script:signedIn) {
        try { $ps = [powershell]::Create(); $ps.Runspace = $rs; [void]$ps.AddScript('Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue').Invoke(); $ps.Dispose() } catch { }
    }
})

$script:forceExit = $false
[void]$win.ShowDialog()
if ($script:forceExit) { [Environment]::Exit(0) }   # a task was still running in the background runspace
$rs.Dispose()
