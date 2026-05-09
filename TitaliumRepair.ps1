# =============================================================================
#   TITALIUM REPAIR TOOL
#   Réparation et optimisation Windows — Interface graphique moderne
#   Auteur : Titalium  (https://titalium.fr)
#   Version : 1.1.0
# =============================================================================
$script:AppVersion = '1.1.0'
# Repo GitHub où sont publiées les releases
$script:GitHubRepo = 'titalium/TitaliumRepair'

#region Auto-élévation
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        if ($PSCommandPath) {
            # Mode .ps1 : relance powershell.exe avec -File
            $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$PSCommandPath`"")
            Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -ErrorAction Stop | Out-Null
        } else {
            # Mode .exe (ps2exe) : relance le .exe lui-même
            $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
            Start-Process -FilePath $exe -Verb RunAs -ErrorAction Stop | Out-Null
        }
    } catch {
        try { [System.Windows.Forms.MessageBox]::Show('Élévation refusée. Le programme nécessite les droits administrateur.', 'Titalium', 'OK', 'Error') | Out-Null } catch {}
    }
    exit
}
#endregion

#region Assemblies WPF
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic
#endregion

#region État partagé
$sync = [hashtable]::Synchronized(@{})
$sync.Busy = $false
$sync.CancelRequested = $false
$sync.AppRoot = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    # En mode .exe (ps2exe), ni $PSScriptRoot ni $MyInvocation.MyCommand.Path ne sont peuplés.
    # On retombe sur le chemin du processus en cours (= le .exe lui-même).
    try { Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
    catch { (Get-Location).Path }
}
$sync.BackupDir = Join-Path $env:USERPROFILE 'Documents\TitaliumRepair\Backups'
$sync.LogDir = Join-Path $env:USERPROFILE 'Documents\TitaliumRepair\Logs'
$sync.WingetUpgrades = New-Object System.Collections.ObjectModel.ObservableCollection[psobject]
$sync.WingetInstalled = New-Object System.Collections.ObjectModel.ObservableCollection[psobject]
$sync.BloatList = New-Object System.Collections.ObjectModel.ObservableCollection[psobject]
$sync.DriverUpdates = New-Object System.Collections.ObjectModel.ObservableCollection[psobject]
$sync.StartupItems = New-Object System.Collections.ObjectModel.ObservableCollection[psobject]
$sync.ServicesItems = New-Object System.Collections.ObjectModel.ObservableCollection[psobject]
$sync.ProcessesItems = New-Object System.Collections.ObjectModel.ObservableCollection[psobject]
# Queue concurrente pour marshaller les updates UI depuis le worker runspace
# vers le thread UI sans utiliser Dispatcher.BeginInvoke (qui pose problème
# avec les scriptblocks créés dans un runspace différent en PowerShell + WPF)
$sync.UIQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[psobject]'
$sync.ProfilesDir = Join-Path $env:USERPROFILE 'Documents\TitaliumRepair\Profiles'
if (-not (Test-Path $sync.ProfilesDir)) { New-Item -ItemType Directory -Force -Path $sync.ProfilesDir | Out-Null }

if (-not (Test-Path $sync.BackupDir)) { New-Item -ItemType Directory -Force -Path $sync.BackupDir | Out-Null }
if (-not (Test-Path $sync.LogDir)) { New-Item -ItemType Directory -Force -Path $sync.LogDir | Out-Null }
#endregion

#region XAML (single-quoted ⇒ pas d'expansion $)
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Titalium Repair Tool"
        Height="800" Width="1320"
        MinHeight="640" MinWidth="1080"
        WindowStartupLocation="CenterScreen"
        Background="#0A0E1A"
        FontFamily="Segoe UI"
        TextOptions.TextFormattingMode="Display"
        TextOptions.TextRenderingMode="ClearType">

  <Window.Resources>
    <SolidColorBrush x:Key="AccentBrush" Color="#00D9FF"/>
    <SolidColorBrush x:Key="AccentDimBrush" Color="#0098B3"/>
    <SolidColorBrush x:Key="DangerBrush" Color="#FF4757"/>
    <SolidColorBrush x:Key="SuccessBrush" Color="#21D07A"/>
    <SolidColorBrush x:Key="WarnBrush" Color="#FFA940"/>
    <SolidColorBrush x:Key="BgBrush" Color="#0A0E1A"/>
    <SolidColorBrush x:Key="PanelBrush" Color="#0F1626"/>
    <SolidColorBrush x:Key="CardBrush" Color="#141B2D"/>
    <SolidColorBrush x:Key="CardHoverBrush" Color="#1A2440"/>
    <SolidColorBrush x:Key="BorderBrush" Color="#1F2A44"/>
    <SolidColorBrush x:Key="TextBrush" Color="#E2E8F0"/>
    <SolidColorBrush x:Key="DimTextBrush" Color="#7B8AA8"/>

    <!-- Bouton d'action générique -->
    <Style x:Key="ActionButton" TargetType="Button">
      <Setter Property="Background" Value="{StaticResource CardBrush}"/>
      <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
      <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="14,9"/>
      <Setter Property="Margin" Value="0,0,8,8"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="MinHeight" Value="38"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="border"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="6">
              <ContentPresenter Margin="{TemplateBinding Padding}"
                                HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="border" Property="Background" Value="{StaticResource CardHoverBrush}"/>
                <Setter TargetName="border" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="border" Property="Background" Value="#0E1623"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Bouton dangereux -->
    <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource ActionButton}">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="border"
                    Background="{TemplateBinding Background}"
                    BorderBrush="#5A1F2A"
                    BorderThickness="1"
                    CornerRadius="6">
              <ContentPresenter Margin="{TemplateBinding Padding}"
                                HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="border" Property="Background" Value="#2A1219"/>
                <Setter TargetName="border" Property="BorderBrush" Value="{StaticResource DangerBrush}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="border" Property="Background" Value="#1A0B10"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Catégorie sidebar -->
    <Style TargetType="ListBoxItem" x:Key="CategoryItem">
      <Setter Property="Foreground" Value="{StaticResource DimTextBrush}"/>
      <Setter Property="Padding" Value="18,11"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="border" Background="Transparent" Padding="{TemplateBinding Padding}">
              <Border.RenderTransform>
                <TranslateTransform x:Name="bordertx" X="0"/>
              </Border.RenderTransform>
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="3"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Rectangle x:Name="indicator" Grid.Column="0" Fill="Transparent" Width="3" HorizontalAlignment="Left"/>
                <ContentPresenter Grid.Column="1" Margin="10,0,0,0" VerticalAlignment="Center"/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="border" Property="Background" Value="#141B2D"/>
                <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="border" Property="Background" Value="#1A2440"/>
                <Setter TargetName="indicator" Property="Fill" Value="{StaticResource AccentBrush}"/>
                <Setter Property="Foreground" Value="White"/>
                <Setter Property="FontWeight" Value="SemiBold"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Card border -->
    <Style x:Key="CardBorder" TargetType="Border">
      <Setter Property="Background" Value="#0F1626"/>
      <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="10"/>
      <Setter Property="Padding" Value="20"/>
      <Setter Property="Margin" Value="0,0,0,16"/>
    </Style>

    <Style x:Key="SectionHeader" TargetType="TextBlock">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontSize" Value="16"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Margin" Value="0,0,0,4"/>
    </Style>
    <Style x:Key="SectionDesc" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource DimTextBrush}"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Margin" Value="0,0,0,16"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>

    <!-- TextBox dark -->
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#0A0E1A"/>
      <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
      <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,7"/>
      <Setter Property="CaretBrush" Value="{StaticResource AccentBrush}"/>
      <Setter Property="SelectionBrush" Value="{StaticResource AccentDimBrush}"/>
    </Style>

    <!-- DataGrid dark -->
    <Style TargetType="DataGrid">
      <Setter Property="Background" Value="#0A0E1A"/>
      <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
      <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="GridLinesVisibility" Value="Horizontal"/>
      <Setter Property="HorizontalGridLinesBrush" Value="#1F2A44"/>
      <Setter Property="RowBackground" Value="Transparent"/>
      <Setter Property="AlternatingRowBackground" Value="#0E1525"/>
      <Setter Property="HeadersVisibility" Value="Column"/>
      <Setter Property="AutoGenerateColumns" Value="False"/>
      <Setter Property="CanUserResizeRows" Value="False"/>
      <Setter Property="RowHeaderWidth" Value="0"/>
    </Style>
    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background" Value="#141B2D"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="10,8"/>
      <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
      <Setter Property="BorderThickness" Value="0,0,1,1"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
    </Style>
    <Style TargetType="DataGridCell">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="DataGridCell">
            <Border Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="DataGridRow">
      <Setter Property="Background" Value="Transparent"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#1A2440"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <!-- ScrollBar minimaliste -->
    <Style TargetType="ScrollBar">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Width" Value="10"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="62"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="200"/>
      <RowDefinition Height="38"/>
    </Grid.RowDefinitions>

    <!-- Canvas particules en fond, derrière tout -->
    <Canvas x:Name="ParticleCanvas" Grid.RowSpan="5" Panel.ZIndex="-10"
            IsHitTestVisible="False" ClipToBounds="True"/>

    <!-- HEADER -->
    <Grid Grid.Row="0" Background="#0F1626">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center" Margin="22,0">
        <Border Width="40" Height="40" CornerRadius="8" Margin="0,0,14,0">
          <Border.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
              <GradientStop Color="#00D9FF" Offset="0"/>
              <GradientStop Color="#0098B3" Offset="1"/>
            </LinearGradientBrush>
          </Border.Background>
          <TextBlock Text="T" FontFamily="Segoe UI" FontSize="22" FontWeight="Bold"
                     Foreground="#0A0E1A" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="TITALIUM REPAIR TOOL" Foreground="White" FontWeight="Bold" FontSize="16"/>
          <TextBlock Text="Réparation et optimisation Windows · v1.0" Foreground="#7B8AA8" FontSize="11"/>
        </StackPanel>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,18,0">
        <Button x:Name="BtnExportLogs" Content="Exporter les logs" Width="140" Style="{StaticResource ActionButton}" Margin="0,0,8,0"/>
        <Button x:Name="BtnClearLogs" Content="Effacer les logs" Width="130" Style="{StaticResource ActionButton}" Margin="0,0,0,0"/>
      </StackPanel>
    </Grid>

    <!-- BANDEAU DE PROGRESSION (visible quand busy) -->
    <Border x:Name="ProgressBanner" Grid.Row="1" Background="#0F1A30" BorderBrush="{StaticResource AccentBrush}"
            BorderThickness="0,1,0,1" Padding="20,10" Visibility="Collapsed">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="80"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" x:Name="BannerTitle" Text="Opération en cours"
                       Foreground="White" FontWeight="SemiBold" FontSize="13" Margin="0,0,12,0"/>
            <TextBlock Grid.Column="1" x:Name="BannerSubtext" Text=""
                       Foreground="#A8E6FF" FontSize="12" TextTrimming="CharacterEllipsis"/>
          </Grid>
          <ProgressBar x:Name="BannerBar" Height="6" Margin="0,8,0,0" Minimum="0" Maximum="100"
                       Background="#1A2332" Foreground="{StaticResource AccentBrush}" BorderThickness="0"
                       IsIndeterminate="True"/>
        </StackPanel>
        <TextBlock Grid.Column="1" x:Name="BannerPct" Text=""
                   Foreground="{StaticResource AccentBrush}" FontWeight="Bold" FontSize="18"
                   HorizontalAlignment="Right" VerticalAlignment="Center"/>
      </Grid>
    </Border>

    <!-- MAIN -->
    <Grid Grid.Row="2">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="240"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- SIDEBAR -->
      <Border Grid.Column="0" Background="#0C1220" BorderBrush="#1F2A44" BorderThickness="0,0,1,0">
        <ListBox x:Name="CategoryList" Background="Transparent" BorderThickness="0"
                 ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                 SelectedIndex="0">
          <ListBoxItem Content="Tableau de bord" Tag="Dashboard" Style="{StaticResource CategoryItem}"/>
          <ListBoxItem Content="Réparation système" Tag="Repair" Style="{StaticResource CategoryItem}"/>
          <ListBoxItem Content="Windows Update" Tag="Update" Style="{StaticResource CategoryItem}"/>
          <ListBoxItem Content="Nettoyage" Tag="Clean" Style="{StaticResource CategoryItem}"/>
          <ListBoxItem Content="Registre" Tag="Registry" Style="{StaticResource CategoryItem}"/>
          <ListBoxItem Content="Réseau" Tag="Network" Style="{StaticResource CategoryItem}"/>
          <ListBoxItem Content="Logiciels (Winget)" Tag="Winget" Style="{StaticResource CategoryItem}"/>
          <ListBoxItem Content="Pilotes" Tag="Drivers" Style="{StaticResource CategoryItem}"/>
          <ListBoxItem Content="Performances" Tag="Performance" Style="{StaticResource CategoryItem}"/>
          <ListBoxItem Content="Sécurité" Tag="Security" Style="{StaticResource CategoryItem}"/>
          <ListBoxItem Content="Récupération" Tag="Recovery" Style="{StaticResource CategoryItem}"/>
          <ListBoxItem Content="Infos système" Tag="Info" Style="{StaticResource CategoryItem}"/>
          <ListBoxItem Content="Outils rapides" Tag="Tools" Style="{StaticResource CategoryItem}"/>
          <ListBoxItem Content="Avancé" Tag="Advanced" Style="{StaticResource CategoryItem}"/>
        </ListBox>
      </Border>

      <!-- CONTENT -->
      <ScrollViewer Grid.Column="1" VerticalScrollBarVisibility="Auto" Padding="24,18">
        <Grid x:Name="PanelHost">
          <!-- ============ TABLEAU DE BORD ============ -->
          <StackPanel x:Name="PanelDashboard" Visibility="Visible">
            <Grid Margin="0,0,0,8">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <StackPanel Grid.Column="0">
                <TextBlock Style="{StaticResource SectionHeader}" Text="Tableau de bord"/>
                <TextBlock Style="{StaticResource SectionDesc}" Text="Vue d'ensemble de la santé du système. Sélectionne une catégorie à gauche pour agir."/>
              </StackPanel>
              <Button Grid.Column="1" x:Name="BtnDashRefresh" Content="Rafraîchir" Width="120" Height="36"
                      Style="{StaticResource ActionButton}" VerticalAlignment="Top"/>
            </Grid>

            <!-- Cartes de santé en grille 3 colonnes -->
            <UniformGrid Columns="3" Rows="0">
              <!-- Disque -->
              <Border Style="{StaticResource CardBorder}" Margin="0,0,12,12">
                <StackPanel>
                  <TextBlock Text="DISQUE C:" Foreground="#7B8AA8" FontSize="11" FontWeight="SemiBold"/>
                  <TextBlock x:Name="CardDisk" Text="—" Foreground="White" FontSize="22" FontWeight="Bold" Margin="0,8,0,4"/>
                  <TextBlock x:Name="CardDiskSub" Text="" Foreground="#7B8AA8" FontSize="11"/>
                  <ProgressBar x:Name="CardDiskBar" Value="0" Maximum="100" Height="5" Margin="0,10,0,0"
                               Background="#1A2332" Foreground="#21D07A" BorderThickness="0"/>
                </StackPanel>
              </Border>
              <!-- Defender -->
              <Border Style="{StaticResource CardBorder}" Margin="6,0,6,12">
                <StackPanel>
                  <TextBlock Text="WINDOWS DEFENDER" Foreground="#7B8AA8" FontSize="11" FontWeight="SemiBold"/>
                  <TextBlock x:Name="CardDefender" Text="—" Foreground="White" FontSize="22" FontWeight="Bold" Margin="0,8,0,4"/>
                  <TextBlock x:Name="CardDefenderSub" Text="" Foreground="#7B8AA8" FontSize="11"/>
                </StackPanel>
              </Border>
              <!-- Windows Update -->
              <Border Style="{StaticResource CardBorder}" Margin="12,0,0,12">
                <StackPanel>
                  <TextBlock Text="MISES À JOUR" Foreground="#7B8AA8" FontSize="11" FontWeight="SemiBold"/>
                  <TextBlock x:Name="CardUpdates" Text="—" Foreground="White" FontSize="22" FontWeight="Bold" Margin="0,8,0,4"/>
                  <TextBlock x:Name="CardUpdatesSub" Text="" Foreground="#7B8AA8" FontSize="11"/>
                </StackPanel>
              </Border>
              <!-- RAM -->
              <Border Style="{StaticResource CardBorder}" Margin="0,0,12,12">
                <StackPanel>
                  <TextBlock Text="MÉMOIRE" Foreground="#7B8AA8" FontSize="11" FontWeight="SemiBold"/>
                  <TextBlock x:Name="CardRam" Text="—" Foreground="White" FontSize="22" FontWeight="Bold" Margin="0,8,0,4"/>
                  <TextBlock x:Name="CardRamSub" Text="" Foreground="#7B8AA8" FontSize="11"/>
                  <ProgressBar x:Name="CardRamBar" Value="0" Maximum="100" Height="5" Margin="0,10,0,0"
                               Background="#1A2332" Foreground="#00D9FF" BorderThickness="0"/>
                </StackPanel>
              </Border>
              <!-- BSOD -->
              <Border Style="{StaticResource CardBorder}" Margin="6,0,6,12">
                <StackPanel>
                  <TextBlock Text="BSOD (30 JOURS)" Foreground="#7B8AA8" FontSize="11" FontWeight="SemiBold"/>
                  <TextBlock x:Name="CardBsod" Text="—" Foreground="White" FontSize="22" FontWeight="Bold" Margin="0,8,0,4"/>
                  <TextBlock x:Name="CardBsodSub" Text="" Foreground="#7B8AA8" FontSize="11"/>
                </StackPanel>
              </Border>
              <!-- Uptime / point de restauration -->
              <Border Style="{StaticResource CardBorder}" Margin="12,0,0,12">
                <StackPanel>
                  <TextBlock Text="UPTIME / RESTAURATION" Foreground="#7B8AA8" FontSize="11" FontWeight="SemiBold"/>
                  <TextBlock x:Name="CardUptime" Text="—" Foreground="White" FontSize="22" FontWeight="Bold" Margin="0,8,0,4"/>
                  <TextBlock x:Name="CardRestore" Text="" Foreground="#7B8AA8" FontSize="11"/>
                </StackPanel>
              </Border>
            </UniformGrid>
          </StackPanel>

          <!-- ============ RÉPARATION SYSTÈME ============ -->
          <StackPanel x:Name="PanelRepair" Visibility="Collapsed">
            <TextBlock Style="{StaticResource SectionHeader}" Text="Réparation système"/>
            <TextBlock Style="{StaticResource SectionDesc}" Text="Vérifie l'intégrité du système, du magasin de composants et des fichiers protégés."/>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Style="{StaticResource SectionHeader}" Text="Diagnostics" FontSize="14"/>
                <WrapPanel>
                  <Button x:Name="BtnSFC" Content="SFC /scannow" Width="200" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnDismCheck" Content="DISM CheckHealth" Width="200" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnDismScan" Content="DISM ScanHealth" Width="200" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnDismRestore" Content="DISM RestoreHealth" Width="200" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnDismAnalyze" Content="DISM AnalyzeComponentStore" Width="240" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnFullRepair" Content="Réparation complète (SFC + DISM)" Width="280" Style="{StaticResource ActionButton}"/>
                </WrapPanel>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Style="{StaticResource SectionHeader}" Text="Composants Windows" FontSize="14"/>
                <WrapPanel>
                  <Button x:Name="BtnReregisterDLLs" Content="Réenregistrer DLL système" Width="240" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnWmi" Content="Vérifier / réparer WMI" Width="220" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnChkdsk" Content="Planifier CHKDSK au reboot" Width="240" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnBcd" Content="Réparer BCD (boot)" Width="200" Style="{StaticResource ActionButton}"/>
                </WrapPanel>
              </StackPanel>
            </Border>
          </StackPanel>

          <!-- ============ WINDOWS UPDATE ============ -->
          <StackPanel x:Name="PanelUpdate" Visibility="Collapsed">
            <TextBlock Style="{StaticResource SectionHeader}" Text="Windows Update"/>
            <TextBlock Style="{StaticResource SectionDesc}" Text="Gère le service Windows Update : reset, recherche manuelle, historique."/>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Style="{StaticResource SectionHeader}" Text="Réparation et recherche" FontSize="14"/>
                <WrapPanel>
                  <Button x:Name="BtnWuReset" Content="Reset complet Windows Update" Width="260" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnWuOpen" Content="Ouvrir Windows Update" Width="200" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnWuHistory" Content="Historique des MAJ installées" Width="240" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnWuPending" Content="Lister MAJ en attente" Width="220" Style="{StaticResource ActionButton}"/>
                </WrapPanel>
              </StackPanel>
            </Border>
          </StackPanel>

          <!-- ============ NETTOYAGE ============ -->
          <StackPanel x:Name="PanelClean" Visibility="Collapsed">
            <TextBlock Style="{StaticResource SectionHeader}" Text="Nettoyage système"/>
            <TextBlock Style="{StaticResource SectionDesc}" Text="Libère de l'espace disque et purge les caches Windows."/>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Style="{StaticResource SectionHeader}" Text="Caches et fichiers temporaires" FontSize="14"/>
                <WrapPanel>
                  <Button x:Name="BtnCleanUserTemp" Content="Vider %TEMP% utilisateur" Width="220" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnCleanWinTemp" Content="Vider C:\Windows\Temp" Width="210" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnCleanPrefetch" Content="Vider Prefetch" Width="170" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnCleanThumbs" Content="Vider miniatures" Width="180" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnCleanRecycle" Content="Vider la corbeille" Width="190" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnCleanSWD" Content="Vider SoftwareDistribution" Width="240" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnCleanCatroot" Content="Vider catroot2" Width="170" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnCleanDeliveryOpt" Content="Vider Delivery Optimization" Width="240" Style="{StaticResource ActionButton}"/>
                </WrapPanel>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Style="{StaticResource SectionHeader}" Text="Nettoyage avancé" FontSize="14"/>
                <WrapPanel>
                  <Button x:Name="BtnCleanmgr" Content="Lancer Disk Cleanup" Width="200" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnCleanmgrSage" Content="Disk Cleanup étendu (sageset)" Width="260" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnCleanBrowsers" Content="Caches navigateurs (Edge, Chrome, FF)" Width="320" Style="{StaticResource DangerButton}"/>
                  <Button x:Name="BtnCleanWinOld" Content="Supprimer Windows.old" Width="220" Style="{StaticResource DangerButton}"/>
                  <Button x:Name="BtnCleanAll" Content="Nettoyage complet (tout vider)" Width="260" Style="{StaticResource DangerButton}"/>
                </WrapPanel>
              </StackPanel>
            </Border>
          </StackPanel>

          <!-- ============ REGISTRE ============ -->
          <StackPanel x:Name="PanelRegistry" Visibility="Collapsed">
            <TextBlock Style="{StaticResource SectionHeader}" Text="Nettoyeur de registre"/>
            <TextBlock Style="{StaticResource SectionDesc}" Text="Sauvegarde, analyse et nettoie les entrées de registre obsolètes. Une sauvegarde est créée automatiquement avant chaque opération."/>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Style="{StaticResource SectionHeader}" Text="Sauvegarde" FontSize="14"/>
                <WrapPanel>
                  <Button x:Name="BtnRegBackup" Content="Sauvegarder le registre complet" Width="260" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnRegOpenBackups" Content="Ouvrir le dossier des backups" Width="240" Style="{StaticResource ActionButton}"/>
                </WrapPanel>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Style="{StaticResource SectionHeader}" Text="Analyse et nettoyage" FontSize="14"/>
                <WrapPanel>
                  <Button x:Name="BtnRegScanUninstall" Content="Désinstallations invalides" Width="240" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnRegScanStartup" Content="Entrées de démarrage mortes" Width="260" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnRegMUICache" Content="Nettoyer MUICache" Width="200" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnRegRecentDocs" Content="Nettoyer RecentDocs" Width="200" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnRegCompact" Content="Compacter la ruche" Width="200" Style="{StaticResource ActionButton}"/>
                </WrapPanel>
              </StackPanel>
            </Border>
          </StackPanel>

          <!-- ============ RÉSEAU ============ -->
          <StackPanel x:Name="PanelNetwork" Visibility="Collapsed">
            <TextBlock Style="{StaticResource SectionHeader}" Text="Outils réseau"/>
            <TextBlock Style="{StaticResource SectionDesc}" Text="Diagnostic et réinitialisation de la pile réseau Windows."/>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Style="{StaticResource SectionHeader}" Text="Diagnostic" FontSize="14"/>
                <WrapPanel>
                  <Button x:Name="BtnNetIpconfig" Content="Afficher config IP" Width="180" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnNetFlushDns" Content="Flush DNS" Width="140" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnNetReleaseRenew" Content="Release / Renew IP" Width="190" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnNetPing" Content="Ping (test connectivité)" Width="220" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnNetTrace" Content="Traceroute" Width="140" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnWifiPasswords" Content="Mots de passe WiFi" Width="200" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnWifiExport" Content="Exporter WiFi (CSV)" Width="200" Style="{StaticResource ActionButton}"/>
                </WrapPanel>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Style="{StaticResource SectionHeader}" Text="Réinitialisation" FontSize="14"/>
                <WrapPanel>
                  <Button x:Name="BtnNetWinsock" Content="Reset Winsock" Width="180" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnNetTcpip" Content="Reset TCP/IP" Width="170" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnNetProxy" Content="Reset proxy WinHTTP" Width="220" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnNetHosts" Content="Réinitialiser le fichier hosts" Width="240" Style="{StaticResource DangerButton}"/>
                  <Button x:Name="BtnNetAll" Content="Reset complet pile réseau" Width="240" Style="{StaticResource DangerButton}"/>
                </WrapPanel>
              </StackPanel>
            </Border>
          </StackPanel>

          <!-- ============ WINGET ============ -->
          <StackPanel x:Name="PanelWinget" Visibility="Collapsed">
            <TextBlock Style="{StaticResource SectionHeader}" Text="Logiciels — Winget"/>
            <TextBlock Style="{StaticResource SectionDesc}" Text="Gestionnaire de paquets Windows. Liste les mises à jour disponibles SANS rien installer automatiquement — sélectionne ce que tu veux mettre à jour."/>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <Grid Margin="0,0,0,12">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <StackPanel Grid.Column="0">
                    <TextBlock Style="{StaticResource SectionHeader}" Text="Mises à jour disponibles" FontSize="14"/>
                    <TextBlock x:Name="WingetCount" Style="{StaticResource SectionDesc}" Margin="0" Text="Cliquez sur « Lister les MAJ » pour analyser."/>
                  </StackPanel>
                  <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Top">
                    <Button x:Name="BtnWingetList" Content="Lister les MAJ" Width="150" Style="{StaticResource ActionButton}" Margin="0,0,8,0"/>
                    <Button x:Name="BtnWingetUpdateSel" Content="Mettre à jour sélection" Width="200" Style="{StaticResource ActionButton}" Margin="0,0,8,0"/>
                    <Button x:Name="BtnWingetUpdateAll" Content="Tout mettre à jour" Width="170" Style="{StaticResource DangerButton}"/>
                  </StackPanel>
                </Grid>
                <DataGrid x:Name="WingetGrid" MinHeight="240" MaxHeight="380" CanUserAddRows="False">
                  <DataGrid.Columns>
                    <DataGridTemplateColumn Header="" Width="40">
                      <DataGridTemplateColumn.CellTemplate>
                        <DataTemplate>
                          <CheckBox IsChecked="{Binding Selected, UpdateSourceTrigger=PropertyChanged, Mode=TwoWay}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </DataTemplate>
                      </DataGridTemplateColumn.CellTemplate>
                    </DataGridTemplateColumn>
                    <DataGridTextColumn Header="Nom" Binding="{Binding Name}" Width="*"/>
                    <DataGridTextColumn Header="Identifiant" Binding="{Binding Id}" Width="2*"/>
                    <DataGridTextColumn Header="Version" Binding="{Binding Version}" Width="120"/>
                    <DataGridTextColumn Header="Disponible" Binding="{Binding Available}" Width="120"/>
                    <DataGridTextColumn Header="Source" Binding="{Binding Source}" Width="100"/>
                  </DataGrid.Columns>
                </DataGrid>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <Grid Margin="0,0,0,12">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <StackPanel Grid.Column="0">
                    <TextBlock Style="{StaticResource SectionHeader}" Text="Logiciels installés" FontSize="14"/>
                    <TextBlock x:Name="InstalledCount" Style="{StaticResource SectionDesc}" Margin="0" Text="Cliquez sur « Lister » pour afficher tous les logiciels installés."/>
                  </StackPanel>
                  <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Top">
                    <TextBox x:Name="InstalledFilter" Width="200" Height="32" Margin="0,0,8,0"
                             VerticalContentAlignment="Center" ToolTip="Filtre rapide (laissez vide pour tout afficher)"/>
                    <Button x:Name="BtnWingetListInstalled" Content="Lister installés" Width="160" Style="{StaticResource ActionButton}" Margin="0,0,8,0"/>
                    <Button x:Name="BtnWingetUninstallSel" Content="Désinstaller sélection" Width="200" Style="{StaticResource DangerButton}"/>
                  </StackPanel>
                </Grid>
                <DataGrid x:Name="InstalledGrid" MinHeight="200" MaxHeight="320" CanUserAddRows="False">
                  <DataGrid.Columns>
                    <DataGridTemplateColumn Header="" Width="40">
                      <DataGridTemplateColumn.CellTemplate>
                        <DataTemplate>
                          <CheckBox IsChecked="{Binding Selected, UpdateSourceTrigger=PropertyChanged, Mode=TwoWay}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </DataTemplate>
                      </DataGridTemplateColumn.CellTemplate>
                    </DataGridTemplateColumn>
                    <DataGridTextColumn Header="Nom" Binding="{Binding Name}" Width="*"/>
                    <DataGridTextColumn Header="Identifiant" Binding="{Binding Id}" Width="2*"/>
                    <DataGridTextColumn Header="Version" Binding="{Binding Version}" Width="120"/>
                    <DataGridTextColumn Header="Source" Binding="{Binding Source}" Width="100"/>
                  </DataGrid.Columns>
                </DataGrid>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Style="{StaticResource SectionHeader}" Text="Autres outils" FontSize="14"/>
                <WrapPanel>
                  <Button x:Name="BtnWingetSearch" Content="Rechercher un logiciel" Width="220" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnWingetInstall" Content="Installer un logiciel" Width="200" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnWingetExport" Content="Exporter la liste" Width="180" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnWingetImport" Content="Importer une liste" Width="190" Style="{StaticResource ActionButton}"/>
                </WrapPanel>
              </StackPanel>
            </Border>
          </StackPanel>

          <!-- ============ PILOTES ============ -->
          <StackPanel x:Name="PanelDrivers" Visibility="Collapsed">
            <TextBlock Style="{StaticResource SectionHeader}" Text="Pilotes"/>
            <TextBlock Style="{StaticResource SectionDesc}" Text="Recherche les mises à jour de pilotes via Windows Update et permet l'inventaire/sauvegarde."/>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <Grid Margin="0,0,0,12">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <StackPanel Grid.Column="0">
                    <TextBlock Style="{StaticResource SectionHeader}" Text="Mises à jour de pilotes" FontSize="14"/>
                    <TextBlock x:Name="DriversCount" Style="{StaticResource SectionDesc}" Margin="0" Text="Cliquez sur « Rechercher » pour interroger Windows Update."/>
                  </StackPanel>
                  <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Top">
                    <Button x:Name="BtnDriversSearch" Content="Rechercher MAJ pilotes" Width="200" Style="{StaticResource ActionButton}" Margin="0,0,8,0"/>
                    <Button x:Name="BtnDriversInstallSel" Content="Installer sélection" Width="180" Style="{StaticResource ActionButton}"/>
                  </StackPanel>
                </Grid>
                <DataGrid x:Name="DriversGrid" MinHeight="200" MaxHeight="320" CanUserAddRows="False">
                  <DataGrid.Columns>
                    <DataGridTemplateColumn Header="" Width="40">
                      <DataGridTemplateColumn.CellTemplate>
                        <DataTemplate>
                          <CheckBox IsChecked="{Binding Selected, UpdateSourceTrigger=PropertyChanged, Mode=TwoWay}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </DataTemplate>
                      </DataGridTemplateColumn.CellTemplate>
                    </DataGridTemplateColumn>
                    <DataGridTextColumn Header="Pilote" Binding="{Binding Title}" Width="*"/>
                    <DataGridTextColumn Header="Catégorie" Binding="{Binding Category}" Width="160"/>
                    <DataGridTextColumn Header="Taille" Binding="{Binding Size}" Width="100"/>
                  </DataGrid.Columns>
                </DataGrid>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Style="{StaticResource SectionHeader}" Text="Inventaire et sauvegarde" FontSize="14"/>
                <WrapPanel>
                  <Button x:Name="BtnDriversList" Content="Lister tous les pilotes" Width="220" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnDriversBackup" Content="Sauvegarder les pilotes" Width="220" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnDriversProblems" Content="Problèmes Device Manager" Width="240" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnDriversUpdate" Content="Ouvrir Windows Update" Width="220" Style="{StaticResource ActionButton}"/>
                </WrapPanel>
              </StackPanel>
            </Border>
          </StackPanel>

          <!-- ============ PERFORMANCES ============ -->
          <StackPanel x:Name="PanelPerformance" Visibility="Collapsed">
            <TextBlock Style="{StaticResource SectionHeader}" Text="Performances"/>
            <TextBlock Style="{StaticResource SectionDesc}" Text="Optimisation du démarrage et des ressources système."/>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <Grid Margin="0,0,0,12">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock Grid.Column="0" Style="{StaticResource SectionHeader}" Text="Programmes au démarrage" FontSize="14"/>
                  <StackPanel Grid.Column="1" Orientation="Horizontal">
                    <Button x:Name="BtnPerfStartup" Content="Lister" Width="100" Style="{StaticResource ActionButton}" Margin="0,0,8,0"/>
                    <Button x:Name="BtnStartupDisable" Content="Désactiver sélection" Width="180" Style="{StaticResource DangerButton}"/>
                  </StackPanel>
                </Grid>
                <DataGrid x:Name="StartupGrid" MinHeight="140" MaxHeight="240" CanUserAddRows="False">
                  <DataGrid.Columns>
                    <DataGridTemplateColumn Header="" Width="40">
                      <DataGridTemplateColumn.CellTemplate>
                        <DataTemplate><CheckBox IsChecked="{Binding Selected, UpdateSourceTrigger=PropertyChanged, Mode=TwoWay}" HorizontalAlignment="Center"/></DataTemplate>
                      </DataGridTemplateColumn.CellTemplate>
                    </DataGridTemplateColumn>
                    <DataGridTextColumn Header="Nom" Binding="{Binding Name}" Width="200"/>
                    <DataGridTextColumn Header="Commande" Binding="{Binding Command}" Width="*"/>
                    <DataGridTextColumn Header="Source" Binding="{Binding Location}" Width="200"/>
                  </DataGrid.Columns>
                </DataGrid>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <Grid Margin="0,0,0,12">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock Grid.Column="0" Style="{StaticResource SectionHeader}" Text="Services Windows" FontSize="14"/>
                  <StackPanel Grid.Column="1" Orientation="Horizontal">
                    <Button x:Name="BtnPerfServices" Content="Lister" Width="100" Style="{StaticResource ActionButton}" Margin="0,0,8,0"/>
                    <Button x:Name="BtnServiceStop" Content="Arrêter sélection" Width="160" Style="{StaticResource DangerButton}" Margin="0,0,8,0"/>
                    <Button x:Name="BtnServiceStart" Content="Démarrer sélection" Width="170" Style="{StaticResource ActionButton}"/>
                  </StackPanel>
                </Grid>
                <DataGrid x:Name="ServicesGrid" MinHeight="140" MaxHeight="240" CanUserAddRows="False">
                  <DataGrid.Columns>
                    <DataGridTemplateColumn Header="" Width="40">
                      <DataGridTemplateColumn.CellTemplate>
                        <DataTemplate><CheckBox IsChecked="{Binding Selected, UpdateSourceTrigger=PropertyChanged, Mode=TwoWay}" HorizontalAlignment="Center"/></DataTemplate>
                      </DataGridTemplateColumn.CellTemplate>
                    </DataGridTemplateColumn>
                    <DataGridTextColumn Header="Nom (interne)" Binding="{Binding Name}" Width="180"/>
                    <DataGridTextColumn Header="Nom convivial" Binding="{Binding DisplayName}" Width="*"/>
                    <DataGridTextColumn Header="Statut" Binding="{Binding Status}" Width="100"/>
                    <DataGridTextColumn Header="Démarrage" Binding="{Binding StartType}" Width="120"/>
                  </DataGrid.Columns>
                </DataGrid>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <Grid Margin="0,0,0,12">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock Grid.Column="0" Style="{StaticResource SectionHeader}" Text="Top processus" FontSize="14"/>
                  <StackPanel Grid.Column="1" Orientation="Horizontal">
                    <Button x:Name="BtnPerfTopProcs" Content="Rafraîchir" Width="120" Style="{StaticResource ActionButton}" Margin="0,0,8,0"/>
                    <Button x:Name="BtnProcessKill" Content="Tuer sélection" Width="160" Style="{StaticResource DangerButton}"/>
                  </StackPanel>
                </Grid>
                <DataGrid x:Name="ProcessesGrid" MinHeight="140" MaxHeight="240" CanUserAddRows="False">
                  <DataGrid.Columns>
                    <DataGridTemplateColumn Header="" Width="40">
                      <DataGridTemplateColumn.CellTemplate>
                        <DataTemplate><CheckBox IsChecked="{Binding Selected, UpdateSourceTrigger=PropertyChanged, Mode=TwoWay}" HorizontalAlignment="Center"/></DataTemplate>
                      </DataGridTemplateColumn.CellTemplate>
                    </DataGridTemplateColumn>
                    <DataGridTextColumn Header="PID" Binding="{Binding Id}" Width="80"/>
                    <DataGridTextColumn Header="Nom" Binding="{Binding Name}" Width="*"/>
                    <DataGridTextColumn Header="CPU (s)" Binding="{Binding Cpu}" Width="100"/>
                    <DataGridTextColumn Header="RAM (Mo)" Binding="{Binding Ram}" Width="120"/>
                  </DataGrid.Columns>
                </DataGrid>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Style="{StaticResource SectionHeader}" Text="Optimisation" FontSize="14"/>
                <WrapPanel>
                  <Button x:Name="BtnPerfPowerHigh" Content="Plan : Performances élevées" Width="240" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnPerfPowerBalanced" Content="Plan : Équilibré" Width="180" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnVisualPerf" Content="Mode performances visuelles" Width="240" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnVisualBest" Content="Restaurer les effets visuels" Width="240" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnHibernateOff" Content="Désactiver l'hibernation" Width="220" Style="{StaticResource DangerButton}"/>
                  <Button x:Name="BtnHibernateOn" Content="Activer l'hibernation" Width="200" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnHibernateStatus" Content="Statut hiberfil.sys" Width="190" Style="{StaticResource ActionButton}"/>
                </WrapPanel>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <Grid Margin="0,0,0,12">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <StackPanel Grid.Column="0">
                    <TextBlock Style="{StaticResource SectionHeader}" Text="Bloatware Windows" FontSize="14"/>
                    <TextBlock x:Name="BloatCount" Style="{StaticResource SectionDesc}" Margin="0" Text="Cliquez sur « Lister » pour analyser les applications préinstallées."/>
                  </StackPanel>
                  <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Top">
                    <Button x:Name="BtnBloatList" Content="Lister bloatware" Width="160" Style="{StaticResource ActionButton}" Margin="0,0,8,0"/>
                    <Button x:Name="BtnBloatRemove" Content="Désinstaller sélection" Width="200" Style="{StaticResource DangerButton}"/>
                  </StackPanel>
                </Grid>
                <DataGrid x:Name="BloatGrid" MinHeight="180" MaxHeight="320" CanUserAddRows="False">
                  <DataGrid.Columns>
                    <DataGridTemplateColumn Header="" Width="40">
                      <DataGridTemplateColumn.CellTemplate>
                        <DataTemplate>
                          <CheckBox IsChecked="{Binding Selected, UpdateSourceTrigger=PropertyChanged, Mode=TwoWay}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </DataTemplate>
                      </DataGridTemplateColumn.CellTemplate>
                    </DataGridTemplateColumn>
                    <DataGridTextColumn Header="Nom convivial" Binding="{Binding DisplayName}" Width="*"/>
                    <DataGridTextColumn Header="Package Appx" Binding="{Binding PackageFullName}" Width="2*"/>
                    <DataGridTextColumn Header="Éditeur" Binding="{Binding Publisher}" Width="160"/>
                  </DataGrid.Columns>
                </DataGrid>
              </StackPanel>
            </Border>
          </StackPanel>

          <!-- ============ SÉCURITÉ ============ -->
          <StackPanel x:Name="PanelSecurity" Visibility="Collapsed">
            <TextBlock Style="{StaticResource SectionHeader}" Text="Sécurité"/>
            <TextBlock Style="{StaticResource SectionDesc}" Text="Windows Defender, MRT et statut de l'activation Windows."/>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Style="{StaticResource SectionHeader}" Text="Windows Defender" FontSize="14"/>
                <WrapPanel>
                  <Button x:Name="BtnDefStatus" Content="Statut Defender" Width="180" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnDefUpdate" Content="MAJ signatures" Width="170" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnDefQuick" Content="Scan rapide" Width="160" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnDefFull" Content="Scan complet" Width="170" Style="{StaticResource ActionButton}"/>
                </WrapPanel>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Style="{StaticResource SectionHeader}" Text="Autres" FontSize="14"/>
                <WrapPanel>
                  <Button x:Name="BtnMrt" Content="Lancer MRT" Width="160" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnActivation" Content="Statut activation Windows" Width="240" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnHashFile" Content="Calculer hash d'un fichier" Width="240" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnTelemetryStatus" Content="Statut télémétrie" Width="200" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnTelemetryOff" Content="Désactiver la télémétrie" Width="240" Style="{StaticResource DangerButton}"/>
                  <Button x:Name="BtnTelemetryOn" Content="Réactiver la télémétrie" Width="220" Style="{StaticResource ActionButton}"/>
                </WrapPanel>
              </StackPanel>
            </Border>
          </StackPanel>

          <!-- ============ RÉCUPÉRATION ============ -->
          <StackPanel x:Name="PanelRecovery" Visibility="Collapsed">
            <TextBlock Style="{StaticResource SectionHeader}" Text="Récupération"/>
            <TextBlock Style="{StaticResource SectionDesc}" Text="Points de restauration et réparation du démarrage."/>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <WrapPanel>
                  <Button x:Name="BtnRecCreatePoint" Content="Créer un point de restauration" Width="260" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnRecListPoints" Content="Lister les points" Width="180" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnRecOpenRstrui" Content="Ouvrir Restauration système" Width="240" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnRecBcd" Content="Réparer le boot (BCD)" Width="220" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnBsodList" Content="Derniers BSOD" Width="180" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnBsodMinidump" Content="Ouvrir dossier minidumps" Width="240" Style="{StaticResource ActionButton}"/>
                </WrapPanel>
              </StackPanel>
            </Border>
          </StackPanel>

          <!-- ============ INFOS SYSTÈME ============ -->
          <StackPanel x:Name="PanelInfo" Visibility="Collapsed">
            <TextBlock Style="{StaticResource SectionHeader}" Text="Informations système"/>
            <TextBlock Style="{StaticResource SectionDesc}" Text="Caractéristiques matérielles et logicielles du poste."/>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <WrapPanel>
                  <Button x:Name="BtnInfoSummary" Content="Récapitulatif système" Width="220" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnInfoCpu" Content="CPU" Width="100" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnInfoRam" Content="RAM" Width="100" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnInfoGpu" Content="GPU" Width="100" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnInfoDisks" Content="Disques" Width="120" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnInfoSmart" Content="Santé disques (SMART)" Width="220" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnInfoBattery" Content="Rapport batterie (laptop)" Width="220" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnInfoUptime" Content="Uptime" Width="120" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnInfoNet" Content="Adresses IP / MAC" Width="200" Style="{StaticResource ActionButton}"/>
                </WrapPanel>
              </StackPanel>
            </Border>
          </StackPanel>

          <!-- ============ OUTILS RAPIDES ============ -->
          <StackPanel x:Name="PanelTools" Visibility="Collapsed">
            <TextBlock Style="{StaticResource SectionHeader}" Text="Outils rapides"/>
            <TextBlock Style="{StaticResource SectionDesc}" Text="Lancement rapide des consoles administratives Windows."/>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <WrapPanel>
                  <Button x:Name="BtnToolRegedit" Content="Éditeur de registre" Width="200" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnToolServices" Content="Services" Width="140" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnToolDevmgmt" Content="Gestionnaire de périphériques" Width="260" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnToolEventvwr" Content="Observateur d'événements" Width="240" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnToolTaskmgr" Content="Gestionnaire des tâches" Width="220" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnToolDiskmgmt" Content="Gestion des disques" Width="200" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnToolMsconfig" Content="msconfig" Width="140" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnToolMsinfo" Content="Informations système" Width="200" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnToolPerfmon" Content="Moniteur de performances" Width="240" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnToolResmon" Content="Moniteur de ressources" Width="220" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnToolControl" Content="Panneau de configuration" Width="240" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnToolSettings" Content="Paramètres Windows" Width="200" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnPrintQueue" Content="Vider file d'impression bloquée" Width="280" Style="{StaticResource ActionButton}"/>
                </WrapPanel>
              </StackPanel>
            </Border>
          </StackPanel>

          <!-- ============ AVANCÉ ============ -->
          <StackPanel x:Name="PanelAdvanced" Visibility="Collapsed">
            <TextBlock Style="{StaticResource SectionHeader}" Text="Avancé"/>
            <TextBlock Style="{StaticResource SectionDesc}" Text="Profils de maintenance personnalisés et raccourcis avancés."/>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Style="{StaticResource SectionHeader}" Text="Profils de maintenance" FontSize="14"/>
                <TextBlock Style="{StaticResource SectionDesc}" Text="Enchaîne automatiquement plusieurs opérations en un clic. Trois profils prédéfinis sont disponibles ; tu peux aussi en créer."/>
                <WrapPanel>
                  <Button x:Name="BtnProfileWeekly" Content="▶  Nettoyage hebdo" Width="220" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnProfileRepair" Content="▶  Réparation système complète" Width="280" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnProfilePresale" Content="▶  Avant vente PC" Width="200" Style="{StaticResource DangerButton}"/>
                </WrapPanel>
                <TextBlock Style="{StaticResource SectionDesc}" Margin="0,12,0,8" Text="Profils personnalisés (sauvegardés en JSON dans Documents\TitaliumRepair\Profiles\) :"/>
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <ListBox x:Name="ProfilesList" Grid.Column="0" Background="#0A0E1A" Foreground="#E2E8F0"
                           BorderBrush="#1F2A44" BorderThickness="1" MinHeight="100" MaxHeight="180"/>
                  <StackPanel Grid.Column="1" Margin="12,0,0,0">
                    <Button x:Name="BtnProfileLoad" Content="Charger" Width="140" Style="{StaticResource ActionButton}"/>
                    <Button x:Name="BtnProfileRun" Content="Exécuter" Width="140" Style="{StaticResource ActionButton}"/>
                    <Button x:Name="BtnProfileNew" Content="Nouveau" Width="140" Style="{StaticResource ActionButton}"/>
                    <Button x:Name="BtnProfileDelete" Content="Supprimer" Width="140" Style="{StaticResource DangerButton}"/>
                    <Button x:Name="BtnProfileFolder" Content="Ouvrir dossier" Width="140" Style="{StaticResource ActionButton}"/>
                  </StackPanel>
                </Grid>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Style="{StaticResource SectionHeader}" Text="Raccourcis administrateur" FontSize="14"/>
                <WrapPanel>
                  <Button x:Name="BtnGodMode" Content="Créer GodMode sur le bureau" Width="260" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnElevatedShell" Content="PowerShell admin" Width="180" Style="{StaticResource ActionButton}"/>
                  <Button x:Name="BtnElevatedCmd" Content="Cmd admin" Width="140" Style="{StaticResource ActionButton}"/>
                </WrapPanel>
              </StackPanel>
            </Border>
          </StackPanel>
        </Grid>
      </ScrollViewer>
    </Grid>

    <!-- CONSOLE -->
    <Border Grid.Row="3" Background="#070B14" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,1,0,0">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="32"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <Grid Grid.Row="0" Background="#0A1020">
          <TextBlock Text="CONSOLE" Foreground="#7B8AA8" FontSize="11" FontWeight="SemiBold" Margin="16,0" VerticalAlignment="Center"/>
        </Grid>
        <TextBox x:Name="LogBox" Grid.Row="1"
                 Background="Transparent" Foreground="#A8E6FF"
                 FontFamily="Consolas, Courier New" FontSize="12"
                 IsReadOnly="True" BorderThickness="0"
                 TextWrapping="NoWrap"
                 VerticalScrollBarVisibility="Auto"
                 HorizontalScrollBarVisibility="Auto"
                 Padding="14,8"/>
      </Grid>
    </Border>

    <!-- STATUS BAR -->
    <Grid Grid.Row="4" Background="#0F1626">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center" Margin="16,0">
        <Ellipse x:Name="StatusDot" Width="8" Height="8" Fill="{StaticResource SuccessBrush}" Margin="0,0,8,0"/>
        <TextBlock x:Name="StatusText" Text="Prêt" Foreground="#A8B5CC" FontSize="12" VerticalAlignment="Center"/>
        <ProgressBar x:Name="MainProgress" Width="220" Height="4" Margin="20,0,0,0"
                     Background="#1A2332" Foreground="#00D9FF" BorderThickness="0"
                     IsIndeterminate="True" Visibility="Collapsed"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,16,0">
        <Button x:Name="BtnCheckUpdate" Content="Vérifier MAJ" Width="110" Height="26" Style="{StaticResource ActionButton}"
                Margin="0,0,8,0" Padding="0" FontSize="11"/>
        <Button x:Name="BtnCancel" Content="Annuler" Width="90" Height="26" Style="{StaticResource ActionButton}"
                IsEnabled="False" Margin="0,0,16,0" Padding="0" FontSize="11"/>
        <TextBlock Foreground="#7B8AA8" FontSize="11" VerticalAlignment="Center">
          <Run Text="Made by "/>
          <Hyperlink x:Name="LinkTitalium" Foreground="{StaticResource AccentBrush}" TextDecorations="None" NavigateUri="https://titalium.fr">
            <Run Text="Titalium" FontWeight="Bold"/>
          </Hyperlink>
          <Run x:Name="VersionRun" Text=" · v1.1.0"/>
        </TextBlock>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
'@
#endregion

#region Parse XAML
$reader = New-Object System.Xml.XmlNodeReader $xaml
try {
    $window = [Windows.Markup.XamlReader]::Load($reader)
} catch {
    [System.Windows.Forms.MessageBox]::Show("Erreur XAML : $($_.Exception.Message)", 'Titalium', 'OK', 'Error') | Out-Null
    exit
}

$ctrl = @{}
$xaml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object {
    $name = $_.Attributes['x:Name'].Value
    if ($name) {
        $ctrl[$name] = $window.FindName($name)
    }
}

$sync.Window = $window
$sync.Log = $ctrl.LogBox
$sync.StatusText = $ctrl.StatusText
$sync.StatusDot = $ctrl.StatusDot
$sync.Progress = $ctrl.MainProgress
$sync.BtnCancel = $ctrl.BtnCancel
$sync.WingetGrid = $ctrl.WingetGrid
$sync.WingetCount = $ctrl.WingetCount
$ctrl.WingetGrid.ItemsSource = $sync.WingetUpgrades
$ctrl.BloatGrid.ItemsSource = $sync.BloatList
$ctrl.DriversGrid.ItemsSource = $sync.DriverUpdates
$ctrl.StartupGrid.ItemsSource = $sync.StartupItems
$ctrl.ServicesGrid.ItemsSource = $sync.ServicesItems
$ctrl.ProcessesGrid.ItemsSource = $sync.ProcessesItems
$ctrl.InstalledGrid.ItemsSource = [System.Windows.Data.CollectionViewSource]::GetDefaultView($sync.WingetInstalled)
$ctrl.InstalledFilter.Add_TextChanged({
    $f = $ctrl.InstalledFilter.Text
    $view = $ctrl.InstalledGrid.ItemsSource
    if ($view) {
        if ([string]::IsNullOrWhiteSpace($f)) { $view.Filter = $null }
        else {
            $needle = $f.ToLowerInvariant()
            $view.Filter = [Predicate[object]]{
                param($it)
                ($it.Name -and $it.Name.ToLowerInvariant().Contains($needle)) -or
                ($it.Id -and $it.Id.ToLowerInvariant().Contains($needle))
            }
        }
    }
})

# Gestionnaire global d'exceptions non gérées du dispatcher : empêche la fermeture silencieuse de l'app
$window.Dispatcher.add_UnhandledException({
    $e = $args[1]
    try {
        $msg = "Une erreur non gérée s'est produite :`r`n`r`n" + $e.Exception.Message + "`r`n`r`nSource :`r`n" + $e.Exception.StackTrace
        [System.Windows.MessageBox]::Show($msg, "Titalium - Erreur", "OK", "Error") | Out-Null
    } catch {}
    $e.Handled = $true
})

# Timer UI qui draine $sync.UIQueue toutes les 80ms.
# Le scriptblock du Tick est créé dans le scope MAIN (= thread UI), donc PowerShell
# l'exécute sur le thread UI quand le DispatcherTimer le déclenche. C'est ce qui
# permet d'éviter l'erreur cross-thread "calling thread cannot access this object".
$sync.UITimer = New-Object System.Windows.Threading.DispatcherTimer
$sync.UITimer.Interval = [TimeSpan]::FromMilliseconds(80)
$sync.UITimer.Add_Tick({
    try {
        $item = $null
        $hadLog = $false
        $count = 0
        while ($sync.UIQueue.TryDequeue([ref]$item) -and $count -lt 200) {
            $count++
            try {
                switch ($item.Action) {
                    'Log' {
                        $sync.Log.AppendText($item.Text + "`r`n")
                        $hadLog = $true
                    }
                    'StatusBusy' {
                        $sync.StatusText.Text = $item.Text
                        $sync.Progress.Visibility = 'Visible'
                        $sync.StatusDot.Fill = [System.Windows.Media.Brushes]::Orange
                        $sync.BtnCancel.IsEnabled = $true
                    }
                    'StatusReady' {
                        $sync.StatusText.Text = 'Prêt'
                        $sync.Progress.Visibility = 'Collapsed'
                        $sync.StatusDot.Fill = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(33, 208, 122))
                        $sync.BtnCancel.IsEnabled = $false
                        $sync.Busy = $false
                    }
                    'WingetClear'  { $sync.WingetUpgrades.Clear() }
                    'WingetAdd'    { $sync.WingetUpgrades.Add($item.Item) }
                    'WingetCount'  { $ctrl.WingetCount.Text = $item.Text }
                    'BloatClear'   { $sync.BloatList.Clear() }
                    'BloatAdd'     { $sync.BloatList.Add($item.Item) }
                    'BloatCount'   { $ctrl.BloatCount.Text = $item.Text }
                    'InstalledClear' { $sync.WingetInstalled.Clear() }
                    'InstalledAdd' { $sync.WingetInstalled.Add($item.Item) }
                    'InstalledCount' { $ctrl.InstalledCount.Text = $item.Text }
                    'DriversClear' { $sync.DriverUpdates.Clear() }
                    'DriversAdd'   { $sync.DriverUpdates.Add($item.Item) }
                    'DriversCount' { $ctrl.DriversCount.Text = $item.Text }
                    'StartupClear' { $sync.StartupItems.Clear() }
                    'StartupAdd'   { $sync.StartupItems.Add($item.Item) }
                    'ServicesClear'{ $sync.ServicesItems.Clear() }
                    'ServicesAdd'  { $sync.ServicesItems.Add($item.Item) }
                    'ProcessesClear'{ $sync.ProcessesItems.Clear() }
                    'ProcessesAdd' { $sync.ProcessesItems.Add($item.Item) }
                    'ProgressShow' {
                        $ctrl.ProgressBanner.Visibility = 'Visible'
                        $ctrl.BannerTitle.Text = $item.Title
                        $ctrl.BannerSubtext.Text = ''
                        $ctrl.BannerBar.IsIndeterminate = $true
                        $ctrl.BannerBar.Value = 0
                        $ctrl.BannerPct.Text = ''
                    }
                    'ProgressHide' {
                        $ctrl.ProgressBanner.Visibility = 'Collapsed'
                    }
                    'ProgressTitle' { $ctrl.BannerTitle.Text = $item.Text }
                    'ProgressSubtext' { $ctrl.BannerSubtext.Text = $item.Text }
                    'ProgressValue' {
                        $ctrl.BannerBar.IsIndeterminate = $false
                        $ctrl.BannerBar.Value = [double]$item.Value
                        $ctrl.BannerPct.Text = ('{0}%' -f [int]$item.Value)
                    }
                    'ProgressIndet' {
                        $ctrl.BannerBar.IsIndeterminate = $true
                        $ctrl.BannerPct.Text = ''
                    }
                }
            } catch {}
        }
        if ($hadLog) { $sync.Log.ScrollToEnd() }
    } catch {}
})
$sync.UITimer.Start()
#endregion

#region Helpers UI / Logging
function UI-Invoke {
    param([scriptblock]$Action)
    if (-not $sync.Window) { return }
    $sync.Window.Dispatcher.BeginInvoke([action]$Action) | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'HH:mm:ss'
    $color = switch ($Level) {
        'ERROR'  { '#FF4757' }
        'WARN'   { '#FFA940' }
        'OK'     { '#21D07A' }
        'TITLE'  { '#00D9FF' }
        default  { '#A8E6FF' }
    }
    $line = "[$ts] $Message"
    UI-Invoke {
        $sync.Log.AppendText("$line`r`n")
        $sync.Log.ScrollToEnd()
    }
    # Persistance fichier
    try {
        $logFile = Join-Path $sync.LogDir ("session-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
        Add-Content -Path $logFile -Value "[$ts][$Level] $Message" -Encoding UTF8
    } catch {}
}

function Write-LogTitle {
    param([string]$Title)
    Write-Log ""
    Write-Log ("═══ {0} ═══" -f $Title.ToUpper()) 'TITLE'
}

function Set-Status {
    param([string]$Text, [bool]$Busy = $false)
    UI-Invoke {
        $sync.StatusText.Text = $Text
        if ($Busy) {
            $sync.Progress.Visibility = 'Visible'
            $sync.StatusDot.Fill = [System.Windows.Media.Brushes]::Orange
            $sync.BtnCancel.IsEnabled = $true
        } else {
            $sync.Progress.Visibility = 'Collapsed'
            $sync.StatusDot.Fill = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(33, 208, 122))
            $sync.BtnCancel.IsEnabled = $false
        }
    }
}

function Confirm-Action {
    param([string]$Message, [string]$Title = 'Confirmation')
    $r = [System.Windows.MessageBox]::Show($Message, $Title, 'YesNo', 'Question')
    return $r -eq 'Yes'
}

function Show-Info {
    param([string]$Message, [string]$Title = 'Titalium')
    [System.Windows.MessageBox]::Show($Message, $Title, 'OK', 'Information') | Out-Null
}

function Show-Warning {
    param([string]$Message, [string]$Title = 'Titalium')
    [System.Windows.MessageBox]::Show($Message, $Title, 'OK', 'Warning') | Out-Null
}

function Prompt-Text {
    param([string]$Prompt, [string]$Title = 'Titalium', [string]$Default = '')
    return [Microsoft.VisualBasic.Interaction]::InputBox($Prompt, $Title, $Default)
}
#endregion

#region Particules animées
$sync.Particles = New-Object System.Collections.Generic.List[psobject]
$sync.ParticleLines = New-Object System.Collections.Generic.List[System.Windows.Shapes.Line]

function Init-Particles {
  try {
    $canvas = $ctrl.ParticleCanvas
    if (-not $canvas) { return }
    $rand = New-Object System.Random
    $count = 38
    $color = [System.Windows.Media.Color]::FromRgb(0, 217, 255)
    $brush = New-Object System.Windows.Media.SolidColorBrush $color
    $brush.Freeze()

    # Particules
    for ($i = 0; $i -lt $count; $i++) {
        $size = 2 + ($rand.NextDouble() * 2.5)
        $e = New-Object System.Windows.Shapes.Ellipse
        $e.Width = $size
        $e.Height = $size
        $e.Fill = $brush
        $e.Opacity = 0.4 + ($rand.NextDouble() * 0.5)
        $w = if ($canvas.ActualWidth -gt 50) { $canvas.ActualWidth } else { 1280 }
        $h = if ($canvas.ActualHeight -gt 50) { $canvas.ActualHeight } else { 720 }
        [System.Windows.Controls.Canvas]::SetLeft($e, $rand.NextDouble() * $w)
        [System.Windows.Controls.Canvas]::SetTop($e, $rand.NextDouble() * $h)
        $canvas.Children.Add($e) | Out-Null
        $p = [pscustomobject]@{
            Ellipse = $e
            X  = [System.Windows.Controls.Canvas]::GetLeft($e)
            Y  = [System.Windows.Controls.Canvas]::GetTop($e)
            VX = (($rand.NextDouble() - 0.5) * 0.8)
            VY = (($rand.NextDouble() - 0.5) * 0.8)
            R  = $size / 2
        }
        $sync.Particles.Add($p)
    }

    # Pool de lignes (connexions)
    $maxLines = 90
    for ($i = 0; $i -lt $maxLines; $i++) {
        $l = New-Object System.Windows.Shapes.Line
        $l.Stroke = $brush
        $l.StrokeThickness = 0.6
        $l.Visibility = 'Collapsed'
        $canvas.Children.Add($l) | Out-Null
        $sync.ParticleLines.Add($l)
    }

    $maxDist = 130
    $maxDistSq = $maxDist * $maxDist

    $sync.MaxDistSq = $maxDistSq

    $sync.RenderTimer = New-Object System.Windows.Threading.DispatcherTimer
    $sync.RenderTimer.Interval = [TimeSpan]::FromMilliseconds(16)
    $sync.RenderTimer.Add_Tick({
      try {
        $cw = $ctrl.ParticleCanvas.ActualWidth
        $ch = $ctrl.ParticleCanvas.ActualHeight
        if ($cw -lt 50 -or $ch -lt 50) { return }

        # Update positions
        foreach ($p in $sync.Particles) {
            $p.X = $p.X + $p.VX
            $p.Y = $p.Y + $p.VY
            if ($p.X -lt 0 -or $p.X -gt $cw) { $p.VX = -$p.VX; $p.X = [Math]::Max(0, [Math]::Min($cw, $p.X)) }
            if ($p.Y -lt 0 -or $p.Y -gt $ch) { $p.VY = -$p.VY; $p.Y = [Math]::Max(0, [Math]::Min($ch, $p.Y)) }
            [System.Windows.Controls.Canvas]::SetLeft($p.Ellipse, $p.X - $p.R)
            [System.Windows.Controls.Canvas]::SetTop($p.Ellipse, $p.Y - $p.R)
        }

        # Connexions entre particules proches
        $lineIdx = 0
        $count = $sync.Particles.Count
        $lineMax = $sync.ParticleLines.Count
        $maxDsq = $sync.MaxDistSq
        for ($i = 0; $i -lt $count -and $lineIdx -lt $lineMax; $i++) {
            $a = $sync.Particles[$i]
            for ($j = $i + 1; $j -lt $count -and $lineIdx -lt $lineMax; $j++) {
                $b = $sync.Particles[$j]
                $dx = $a.X - $b.X
                $dy = $a.Y - $b.Y
                $dsq = $dx * $dx + $dy * $dy
                if ($dsq -lt $maxDsq) {
                    $line = $sync.ParticleLines[$lineIdx]
                    $line.X1 = $a.X
                    $line.Y1 = $a.Y
                    $line.X2 = $b.X
                    $line.Y2 = $b.Y
                    $opacity = 0.45 * (1 - ($dsq / $maxDsq))
                    $line.Opacity = $opacity
                    $line.Visibility = 'Visible'
                    $lineIdx++
                }
            }
        }
        # Cacher les lignes inutilisées
        for ($k = $lineIdx; $k -lt $lineMax; $k++) {
            $l = $sync.ParticleLines[$k]
            if ($l.Visibility -eq 'Visible') { $l.Visibility = 'Collapsed' }
        }
      } catch {
        # Avale silencieusement les erreurs par frame pour ne pas crasher l'app
      }
    })
    $sync.RenderTimer.Start()
  } catch {
    try { Write-Log "Init-Particles : $($_.Exception.Message)" 'WARN' } catch {}
  }
}
#endregion

#region Worker runspace
$runspace = [runspacefactory]::CreateRunspace()
$runspace.ApartmentState = 'STA'
$runspace.ThreadOptions = 'ReuseThread'
$runspace.Open()
$runspace.SessionStateProxy.SetVariable('sync', $sync)
$sync.Runspace = $runspace

function Invoke-Async {
    param(
        [Parameter(Mandatory)] [scriptblock]$Action,
        [string]$StatusText = 'Opération en cours...'
    )
    if ($sync.Busy) {
        Show-Warning 'Une opération est déjà en cours. Veuillez patienter ou annuler.'
        return
    }
    $sync.Busy = $true
    $sync.CancelRequested = $false
    Set-Status $StatusText $true
    # Affiche le bandeau de progression
    $sync.UIQueue.Enqueue([pscustomobject]@{ Action='ProgressShow'; Title=$StatusText })

    $ps = [PowerShell]::Create()
    $ps.Runspace = $sync.Runspace
    [void]$ps.AddScript({
        param($action)
        try { & $action }
        catch {
            $msg = $_.Exception.Message
            $sync.UIQueue.Enqueue([pscustomobject]@{ Action='Log'; Text="[ERROR] $msg" })
        }
        finally {
            $sync.UIQueue.Enqueue([pscustomobject]@{ Action='ProgressHide' })
            $sync.UIQueue.Enqueue([pscustomobject]@{ Action='StatusReady' })
        }
    }).AddArgument($Action)

    $async = $ps.BeginInvoke()
    # On stocke pour cleanup si annulation
    $sync.CurrentPS = $ps
    $sync.CurrentAsync = $async
}
#endregion

#region Fonctions utilitaires runspace (sérialisées dans le worker)
$runspace.SessionStateProxy.SetVariable('sync', $sync)

# On définit les fonctions de log dans le runspace via un script d'init.
# IMPORTANT : ces fonctions utilisent $sync.UIQueue (ConcurrentQueue) pour
# transmettre les updates UI au thread principal — pas Dispatcher.BeginInvoke
# qui pose des problèmes cross-runspace en PS+WPF.
$initScript = @'
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'HH:mm:ss'
    $line = "[$ts] $Message"
    $sync.UIQueue.Enqueue([pscustomobject]@{ Action='Log'; Text=$line })
    try {
        $logFile = Join-Path $sync.LogDir ("session-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
        Add-Content -Path $logFile -Value "[$ts][$Level] $Message" -Encoding UTF8
    } catch {}
}
function Write-LogTitle {
    param([string]$Title)
    Write-Log ""
    Write-Log ("═══ {0} ═══" -f $Title.ToUpper()) 'TITLE'
}
function Set-Status {
    param([string]$Text)
    $sync.UIQueue.Enqueue([pscustomobject]@{ Action='StatusBusy'; Text=$Text })
}
function Run-Process {
    param([string]$File, [string]$Arguments = '', [switch]$NoOutput)
    Write-Log "→ $File $Arguments"
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $File
        $psi.Arguments = $Arguments
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::GetEncoding(850)
        $psi.StandardErrorEncoding = [System.Text.Encoding]::GetEncoding(850)
        $p = [System.Diagnostics.Process]::Start($psi)
        if (-not $NoOutput) {
            $charBuf = New-Object System.Text.StringBuilder
            $progressRegex = [regex]'(\d{1,3}(?:[.,]\d+)?)\s*%'
            $reader = $p.StandardOutput
            while ($true) {
                if ($sync.CancelRequested) {
                    try { $p.Kill() } catch {}
                    Write-Log "Annulé par l'utilisateur." 'WARN'
                    return
                }
                $ch = $reader.Read()
                if ($ch -lt 0) { break }
                $c = [char]$ch
                if ($c -eq "`n" -or $c -eq "`r") {
                    $line = $charBuf.ToString().Trim()
                    [void]$charBuf.Clear()
                    if ($line) {
                        Write-Log "  $line"
                        # Détecte un pourcentage en sous-texte
                        $m = $progressRegex.Match($line)
                        if ($m.Success) {
                            $pct = [double]($m.Groups[1].Value -replace ',', '.')
                            if ($pct -ge 0 -and $pct -le 100) {
                                $sync.UIQueue.Enqueue([pscustomobject]@{ Action='ProgressValue'; Value=$pct })
                                $sync.UIQueue.Enqueue([pscustomobject]@{ Action='ProgressSubtext'; Text=$line })
                            }
                        } else {
                            $sync.UIQueue.Enqueue([pscustomobject]@{ Action='ProgressSubtext'; Text=$line })
                        }
                    }
                } else {
                    [void]$charBuf.Append($c)
                    # Detection de % "live" sans newline (SFC affiche par exemple "Verification 12% complete..." sur la même ligne)
                    if ($charBuf.Length -gt 4 -and $c -eq '%') {
                        $partial = $charBuf.ToString()
                        $m = $progressRegex.Match($partial)
                        if ($m.Success) {
                            $pct = [double]($m.Groups[1].Value -replace ',', '.')
                            if ($pct -ge 0 -and $pct -le 100) {
                                $sync.UIQueue.Enqueue([pscustomobject]@{ Action='ProgressValue'; Value=$pct })
                            }
                        }
                    }
                }
            }
            # Flush du buffer restant
            $tail = $charBuf.ToString().Trim()
            if ($tail) { Write-Log "  $tail" }
            $err = $p.StandardError.ReadToEnd()
            if ($err -and $err.Trim()) { Write-Log "  $err" 'WARN' }
        }
        $p.WaitForExit()
        return $p.ExitCode
    } catch {
        Write-Log "Erreur : $($_.Exception.Message)" 'ERROR'
        return -1
    }
}
'@

# Les fonctions Write-Log, Run-Process, etc. sont injectées dans CHAQUE scriptblock async via Wrap-Action.
# Cela évite les problèmes de portée des fonctions à travers les pipelines du runspace.
function Wrap-Action {
    param([scriptblock]$Action)
    $combined = [scriptblock]::Create($initScript + "`n" + $Action.ToString())
    return $combined
}
#endregion

#region === FONCTIONS DE RÉPARATION ===

# ----- Réparation système -----
function Op-SFC {
    Wrap-Action {
        Write-LogTitle "SFC /scannow"
        Run-Process 'sfc.exe' '/scannow'
        Write-Log "SFC terminé." 'OK'
    }
}
function Op-DismCheck {
    Wrap-Action {
        Write-LogTitle "DISM /CheckHealth"
        Run-Process 'dism.exe' '/Online /Cleanup-Image /CheckHealth'
        Write-Log "DISM CheckHealth terminé." 'OK'
    }
}
function Op-DismScan {
    Wrap-Action {
        Write-LogTitle "DISM /ScanHealth"
        Run-Process 'dism.exe' '/Online /Cleanup-Image /ScanHealth'
        Write-Log "DISM ScanHealth terminé." 'OK'
    }
}
function Op-DismRestore {
    Wrap-Action {
        Write-LogTitle "DISM /RestoreHealth"
        Run-Process 'dism.exe' '/Online /Cleanup-Image /RestoreHealth'
        Write-Log "DISM RestoreHealth terminé." 'OK'
    }
}
function Op-DismAnalyze {
    Wrap-Action {
        Write-LogTitle "DISM /AnalyzeComponentStore"
        Run-Process 'dism.exe' '/Online /Cleanup-Image /AnalyzeComponentStore'
        Write-Log "Analyse du magasin de composants terminée." 'OK'
    }
}
function Op-FullRepair {
    Wrap-Action {
        Write-LogTitle "Réparation complète"
        Write-Log "Étape 1/4 : DISM CheckHealth"
        Run-Process 'dism.exe' '/Online /Cleanup-Image /CheckHealth'
        Write-Log "Étape 2/4 : DISM ScanHealth"
        Run-Process 'dism.exe' '/Online /Cleanup-Image /ScanHealth'
        Write-Log "Étape 3/4 : DISM RestoreHealth"
        Run-Process 'dism.exe' '/Online /Cleanup-Image /RestoreHealth'
        Write-Log "Étape 4/4 : SFC /scannow"
        Run-Process 'sfc.exe' '/scannow'
        Write-Log "Réparation complète terminée." 'OK'
    }
}
function Op-ReregisterDLLs {
    Wrap-Action {
        Write-LogTitle "Réenregistrement des DLL système"
        $dlls = @(
            'atl.dll','urlmon.dll','mshtml.dll','shdocvw.dll','browseui.dll',
            'jscript.dll','vbscript.dll','scrrun.dll','msxml.dll','msxml3.dll',
            'msxml6.dll','actxprxy.dll','softpub.dll','wintrust.dll','dssenh.dll',
            'rsaenh.dll','gpkcsp.dll','sccbase.dll','slbcsp.dll','cryptdlg.dll',
            'oleaut32.dll','ole32.dll','shell32.dll','initpki.dll','wuapi.dll',
            'wuaueng.dll','wucltui.dll','wups.dll','wups2.dll','wuweb.dll',
            'qmgr.dll','qmgrprxy.dll','wucltux.dll','muweb.dll','wuwebv.dll'
        )
        foreach ($d in $dlls) {
            if ($sync.CancelRequested) { Write-Log "Annulé." 'WARN'; return }
            Run-Process 'regsvr32.exe' "/s $d" -NoOutput
            Write-Log "  ✓ $d"
        }
        Write-Log "Toutes les DLL ont été réenregistrées." 'OK'
    }
}
function Op-Wmi {
    Wrap-Action {
        Write-LogTitle "Vérification WMI"
        $code = Run-Process 'winmgmt.exe' '/verifyrepository'
        if ($code -ne 0) {
            Write-Log "Problème WMI détecté. Tentative de réparation..." 'WARN'
            Run-Process 'winmgmt.exe' '/salvagerepository'
        } else {
            Write-Log "WMI sain." 'OK'
        }
    }
}
function Op-Chkdsk {
    Wrap-Action {
        Write-LogTitle "CHKDSK"
        Write-Log "Planification de CHKDSK C: /F /R au prochain redémarrage..."
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'cmd.exe'
        $psi.Arguments = '/c echo Y | chkdsk C: /F /R'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit()
        Write-Log "CHKDSK programmé. Redémarrez pour l'exécuter." 'OK'
    }
}
function Op-Bcd {
    Wrap-Action {
        Write-LogTitle "Réparation BCD"
        Run-Process 'bootrec.exe' '/scanos'
        Run-Process 'bootrec.exe' '/fixmbr'
        Run-Process 'bootrec.exe' '/fixboot'
        Run-Process 'bootrec.exe' '/rebuildbcd'
        Write-Log "Réparation BCD terminée." 'OK'
    }
}

# ----- Windows Update -----
function Op-WuReset {
    Wrap-Action {
        Write-LogTitle "Reset Windows Update"
        $services = 'bits','wuauserv','appidsvc','cryptsvc'
        foreach ($s in $services) {
            Write-Log "Arrêt service : $s"
            Run-Process 'net.exe' "stop $s" -NoOutput
        }
        Write-Log "Suppression du dossier SoftwareDistribution..."
        $sd = Join-Path $env:windir 'SoftwareDistribution'
        try { Remove-Item -Path "$sd\*" -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        Write-Log "Suppression du dossier catroot2..."
        $cr = Join-Path $env:windir 'System32\catroot2'
        try { Remove-Item -Path "$cr\*" -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        foreach ($s in $services) {
            Write-Log "Démarrage service : $s"
            Run-Process 'net.exe' "start $s" -NoOutput
        }
        Write-Log "Reset Windows Update terminé." 'OK'
    }
}
function Op-WuOpen {
    Wrap-Action {
        Write-LogTitle "Ouverture de Windows Update"
        Start-Process 'ms-settings:windowsupdate'
        Write-Log "Settings ouvert." 'OK'
    }
}
function Op-WuHistory {
    Wrap-Action {
        Write-LogTitle "Historique Windows Update"
        try {
            $session = New-Object -ComObject Microsoft.Update.Session
            $searcher = $session.CreateUpdateSearcher()
            $count = $searcher.GetTotalHistoryCount()
            if ($count -eq 0) { Write-Log "Aucun historique." 'WARN'; return }
            $hist = $searcher.QueryHistory(0, [Math]::Min($count, 50))
            foreach ($h in $hist) {
                $r = switch ($h.ResultCode) { 1 {'En cours'} 2 {'Réussi'} 3 {'Réussi avec erreurs'} 4 {'Échec'} 5 {'Annulé'} default {'?'} }
                Write-Log ("  [{0}] {1} — {2}" -f $h.Date.ToString('yyyy-MM-dd'), $r, $h.Title)
            }
            Write-Log "Affiché : $($hist.Count) MAJ sur $count." 'OK'
        } catch {
            Write-Log "Erreur : $($_.Exception.Message)" 'ERROR'
        }
    }
}
function Op-WuPending {
    Wrap-Action {
        Write-LogTitle "MAJ Windows en attente"
        try {
            $session = New-Object -ComObject Microsoft.Update.Session
            $searcher = $session.CreateUpdateSearcher()
            Write-Log "Recherche en cours (cela peut prendre quelques minutes)..."
            $r = $searcher.Search("IsInstalled=0 and Type='Software'")
            if ($r.Updates.Count -eq 0) {
                Write-Log "Aucune mise à jour en attente." 'OK'
            } else {
                Write-Log "$($r.Updates.Count) mise(s) à jour disponible(s) :" 'TITLE'
                foreach ($u in $r.Updates) {
                    $sz = if ($u.MaxDownloadSize) { '{0:N1} Mo' -f ($u.MaxDownloadSize / 1MB) } else { '?' }
                    Write-Log "  • $($u.Title) ($sz)"
                }
            }
        } catch {
            Write-Log "Erreur : $($_.Exception.Message)" 'ERROR'
        }
    }
}

# ----- Nettoyage -----
function Get-DirSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        $s = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        return ([long]$s)
    } catch { return 0 }
}
function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} Go' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} Mo' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} Ko' -f ($Bytes / 1KB)) }
    return "$Bytes o"
}

function Op-CleanUserTemp {
    Wrap-Action {
        Write-LogTitle "Nettoyage : %TEMP% utilisateur"
        $path = $env:TEMP
        if (-not (Test-Path $path)) { Write-Log "$path n'existe pas." 'WARN'; return }
        $before = (Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $f = if ($before -ge 1GB) { '{0:N2} Go' -f ($before/1GB) } elseif ($before -ge 1MB) { '{0:N1} Mo' -f ($before/1MB) } else { '{0:N1} Ko' -f ($before/1KB) }
        Write-Log "Taille : $f"
        $d=0;$x=0; Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -EA Stop; $d++ } catch { $x++ } }
        Write-Log "Supprimé : $d. Verrouillés : $x." 'OK'
    }
}
function Op-CleanWinTemp {
    Wrap-Action {
        Write-LogTitle "Nettoyage : C:\Windows\Temp"
        $path = "$env:windir\Temp"
        if (-not (Test-Path $path)) { Write-Log "$path n'existe pas." 'WARN'; return }
        $d=0;$x=0; Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -EA Stop; $d++ } catch { $x++ } }
        Write-Log "Supprimé : $d. Verrouillés : $x." 'OK'
    }
}
function Op-CleanPrefetch {
    Wrap-Action {
        Write-LogTitle "Nettoyage : Prefetch"
        $path = "$env:windir\Prefetch"
        if (-not (Test-Path $path)) { Write-Log "$path n'existe pas." 'WARN'; return }
        $d=0;$x=0; Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue -Filter '*.pf' | ForEach-Object { try { Remove-Item $_.FullName -Force -EA Stop; $d++ } catch { $x++ } }
        Write-Log "Supprimé : $d fichiers .pf. Verrouillés : $x." 'OK'
    }
}
function Op-CleanThumbs {
    Wrap-Action {
        Write-LogTitle "Nettoyage : miniatures"
        Run-Process 'cmd.exe' '/c taskkill /f /im explorer.exe' -NoOutput
        Start-Sleep -Milliseconds 500
        $path = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
        if (Test-Path $path) {
            $d=0;Get-ChildItem -Path $path -Filter 'thumbcache_*.db' -Force -EA SilentlyContinue | ForEach-Object { try { Remove-Item $_.FullName -Force -EA Stop; $d++ } catch {} }
            Write-Log "Caches miniatures supprimés : $d." 'OK'
        }
        Start-Process explorer.exe
    }
}
function Op-CleanRecycle {
    Wrap-Action {
        Write-LogTitle "Vidage de la corbeille"
        try {
            Clear-RecycleBin -Force -ErrorAction Stop
            Write-Log "Corbeille vidée." 'OK'
        } catch { Write-Log "Erreur : $($_.Exception.Message)" 'ERROR' }
    }
}
function Op-CleanSWD {
    Wrap-Action {
        Write-LogTitle "Nettoyage : SoftwareDistribution"
        Run-Process 'net.exe' 'stop wuauserv' -NoOutput
        Run-Process 'net.exe' 'stop bits' -NoOutput
        $path = "$env:windir\SoftwareDistribution"
        $d=0;$x=0; Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -EA Stop; $d++ } catch { $x++ } }
        Run-Process 'net.exe' 'start bits' -NoOutput
        Run-Process 'net.exe' 'start wuauserv' -NoOutput
        Write-Log "Supprimé : $d. Verrouillés : $x." 'OK'
    }
}
function Op-CleanCatroot {
    Wrap-Action {
        Write-LogTitle "Nettoyage : catroot2"
        Run-Process 'net.exe' 'stop cryptsvc' -NoOutput
        $path = "$env:windir\System32\catroot2"
        $d=0;$x=0; Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -EA Stop; $d++ } catch { $x++ } }
        Run-Process 'net.exe' 'start cryptsvc' -NoOutput
        Write-Log "Supprimé : $d. Verrouillés : $x." 'OK'
    }
}
function Op-CleanDeliveryOpt {
    Wrap-Action {
        Write-LogTitle "Nettoyage : Delivery Optimization"
        Run-Process 'net.exe' 'stop dosvc' -NoOutput
        $path = "$env:windir\SoftwareDistribution\DeliveryOptimization"
        if (Test-Path $path) {
            $d=0; Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -EA Stop; $d++ } catch {} }
            Write-Log "Supprimé : $d." 'OK'
        } else { Write-Log "Dossier introuvable." 'WARN' }
        Run-Process 'net.exe' 'start dosvc' -NoOutput
    }
}
function Op-CleanmgrSimple {
    Wrap-Action {
        Write-LogTitle "Disk Cleanup"
        Run-Process 'cleanmgr.exe' '/d C'
    }
}
function Op-CleanmgrSage {
    Wrap-Action {
        Write-LogTitle "Disk Cleanup étendu (sageset)"
        Write-Log "Configuration des options : cleanmgr /sageset:1"
        Start-Process 'cleanmgr.exe' '/sageset:1'
        Start-Sleep -Seconds 2
        Run-Process 'cleanmgr.exe' '/sagerun:1'
    }
}
function Op-CleanWinOld {
    Wrap-Action {
        Write-LogTitle "Suppression de Windows.old"
        $path = 'C:\Windows.old'
        if (-not (Test-Path $path)) { Write-Log "Windows.old n'existe pas." 'WARN'; return }
        $d=0;$x=0; Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -EA Stop; $d++ } catch { $x++ } }
        try { Remove-Item -Path $path -Recurse -Force -EA SilentlyContinue } catch {}
        Write-Log "Windows.old supprimé." 'OK'
    }
}
function Op-CleanAll {
    Wrap-Action {
        Write-LogTitle "Nettoyage complet"
        $paths = @(
            @{P=$env:TEMP; L='%TEMP% utilisateur'},
            @{P="$env:windir\Temp"; L='Windows\Temp'},
            @{P="$env:windir\Prefetch"; L='Prefetch'},
            @{P="$env:windir\SoftwareDistribution\Download"; L='SoftwareDistribution\Download'}
        )
        $totalDel = 0
        foreach ($pp in $paths) {
            if (-not (Test-Path $pp.P)) { continue }
            Write-Log "→ $($pp.L)"
            $d=0; Get-ChildItem -Path $pp.P -Force -ErrorAction SilentlyContinue | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -EA Stop; $d++ } catch {} }
            Write-Log "  $d éléments supprimés"
            $totalDel += $d
        }
        try { Clear-RecycleBin -Force -EA SilentlyContinue } catch {}
        Write-Log "Nettoyage complet : $totalDel éléments." 'OK'
    }
}

# ----- Registre -----
function Op-RegBackup {
    Wrap-Action {
        Write-LogTitle "Sauvegarde du registre"
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $hives = @(
            @{Name='HKLM_SOFTWARE'; Path='HKLM\SOFTWARE'},
            @{Name='HKLM_SYSTEM'; Path='HKLM\SYSTEM'},
            @{Name='HKCU'; Path='HKCU'},
            @{Name='HKCR'; Path='HKCR'}
        )
        foreach ($h in $hives) {
            $file = Join-Path $sync.BackupDir "registry-$($h.Name)-$stamp.reg"
            Write-Log "Export $($h.Path) → $file"
            Run-Process 'reg.exe' "export `"$($h.Path)`" `"$file`" /y" -NoOutput
        }
        Write-Log "Sauvegarde terminée dans : $($sync.BackupDir)" 'OK'
    }
}
function Op-RegOpenBackups {
    Wrap-Action {
        Start-Process explorer.exe $sync.BackupDir
        Write-Log "Dossier ouvert : $($sync.BackupDir)" 'OK'
    }
}
function Op-RegScanUninstall {
    Wrap-Action {
        Write-LogTitle "Désinstallations invalides"
        $paths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        )
        $invalid = @()
        foreach ($p in $paths) {
            if (-not (Test-Path $p)) { continue }
            Get-ChildItem -Path $p -ErrorAction SilentlyContinue | ForEach-Object {
                $v = $_.GetValue('UninstallString')
                $name = $_.GetValue('DisplayName')
                if ($v -and $name) {
                    $cmd = $v -replace '^"([^"]+)".*$','$1'
                    $cmd = $cmd -replace '^([^ ]+).*$','$1'
                    $cmd = [Environment]::ExpandEnvironmentVariables($cmd)
                    if ($cmd -and -not (Test-Path -LiteralPath $cmd) -and $cmd -notlike '*MsiExec*') {
                        $invalid += [pscustomobject]@{ Name=$name; Path=$_.PSPath; Cmd=$cmd }
                    }
                }
            }
        }
        if ($invalid.Count -eq 0) {
            Write-Log "Aucune entrée invalide détectée." 'OK'
        } else {
            Write-Log "$($invalid.Count) entrée(s) potentiellement invalide(s) :" 'WARN'
            foreach ($i in $invalid) { Write-Log "  • $($i.Name) [$($i.Cmd)]" }
            Write-Log "Inspectez manuellement avant suppression (regedit)." 'WARN'
        }
    }
}
function Op-RegScanStartup {
    Wrap-Action {
        Write-LogTitle "Entrées de démarrage mortes"
        $keys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
        )
        $dead = @()
        foreach ($k in $keys) {
            if (-not (Test-Path $k)) { continue }
            $r = Get-Item $k
            foreach ($n in $r.Property) {
                $v = $r.GetValue($n)
                $cmd = $v -replace '^"([^"]+)".*$','$1' -replace '^([^ ]+).*$','$1'
                $cmd = [Environment]::ExpandEnvironmentVariables($cmd)
                if ($cmd -and -not (Test-Path -LiteralPath $cmd)) {
                    $dead += [pscustomobject]@{ Key=$k; Name=$n; Cmd=$cmd }
                }
            }
        }
        if ($dead.Count -eq 0) { Write-Log "Aucune entrée morte détectée." 'OK' }
        else {
            Write-Log "$($dead.Count) entrée(s) morte(s) :" 'WARN'
            foreach ($d in $dead) { Write-Log "  • $($d.Name) → $($d.Cmd)" }
        }
    }
}
function Op-RegMUICache {
    Wrap-Action {
        Write-LogTitle "Nettoyage MUICache"
        if (-not $sync.ConfirmedMuiCache) { return }
        $key = 'HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'
        if (-not (Test-Path $key)) { Write-Log "MUICache introuvable." 'WARN'; return }
        $count = 0
        $r = Get-Item $key
        foreach ($n in $r.Property) {
            try {
                $v = $r.GetValue($n)
                $exe = ($n -split '\.')[0]
                if (Test-Path $exe -PathType Leaf) { continue }
                Remove-ItemProperty -Path $key -Name $n -ErrorAction Stop
                $count++
            } catch {}
        }
        Write-Log "$count entrée(s) MUICache supprimée(s)." 'OK'
    }
}
function Op-RegRecentDocs {
    Wrap-Action {
        Write-LogTitle "Nettoyage RecentDocs"
        $key = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs'
        if (-not (Test-Path $key)) { Write-Log "RecentDocs introuvable." 'WARN'; return }
        try {
            Remove-Item -Path $key -Recurse -Force -ErrorAction Stop
            Write-Log "RecentDocs nettoyé." 'OK'
        } catch { Write-Log "Erreur : $($_.Exception.Message)" 'ERROR' }
    }
}
function Op-RegCompact {
    Wrap-Action {
        Write-LogTitle "Compactage du registre (au prochain reboot)"
        Write-Log "Note : la défragmentation du registre s'effectue lors du prochain démarrage."
        Write-Log "Aucune action immédiate, le registre Windows 10/11 se compacte automatiquement." 'OK'
    }
}

# ----- Réseau -----
function Op-NetIpconfig { Wrap-Action { Write-LogTitle "Configuration IP"; Run-Process 'ipconfig.exe' '/all' } }
function Op-NetFlushDns { Wrap-Action { Write-LogTitle "Flush DNS"; Run-Process 'ipconfig.exe' '/flushdns'; Write-Log "DNS vidé." 'OK' } }
function Op-NetReleaseRenew {
    Wrap-Action {
        Write-LogTitle "Release / Renew IP"
        Run-Process 'ipconfig.exe' '/release'
        Start-Sleep -Seconds 1
        Run-Process 'ipconfig.exe' '/renew'
        Write-Log "Bail IP renouvelé." 'OK'
    }
}
function Op-NetPing {
    Wrap-Action {
        Write-LogTitle "Test de connectivité"
        Run-Process 'ping.exe' '-n 4 8.8.8.8'
        Run-Process 'ping.exe' '-n 4 google.com'
    }
}
function Op-NetTrace {
    Wrap-Action {
        Write-LogTitle "Traceroute"
        Run-Process 'tracert.exe' '-d -h 15 8.8.8.8'
    }
}
function Op-NetWinsock {
    Wrap-Action {
        Write-LogTitle "Reset Winsock"
        Run-Process 'netsh.exe' 'winsock reset'
        Write-Log "Reset effectué. Redémarrage requis." 'OK'
    }
}
function Op-NetTcpip {
    Wrap-Action {
        Write-LogTitle "Reset TCP/IP"
        Run-Process 'netsh.exe' 'int ip reset'
        Write-Log "Reset effectué. Redémarrage requis." 'OK'
    }
}
function Op-NetProxy {
    Wrap-Action {
        Write-LogTitle "Reset proxy WinHTTP"
        Run-Process 'netsh.exe' 'winhttp reset proxy'
        Write-Log "Proxy WinHTTP réinitialisé." 'OK'
    }
}
function Op-NetHosts {
    Wrap-Action {
        Write-LogTitle "Réinitialisation du fichier hosts"
        $hosts = "$env:windir\System32\drivers\etc\hosts"
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $bak = Join-Path $sync.BackupDir "hosts-$stamp.bak"
        if (Test-Path $hosts) {
            Copy-Item $hosts $bak -Force
            Write-Log "Backup → $bak" 'OK'
        }
        $default = "# Copyright (c) 1993-2009 Microsoft Corp.`r`n# Fichier hosts par défaut Windows`r`n#`r`n127.0.0.1       localhost`r`n::1             localhost`r`n"
        Set-Content -Path $hosts -Value $default -Encoding ASCII -Force
        Write-Log "Hosts réinitialisé." 'OK'
    }
}
function Op-NetAll {
    Wrap-Action {
        Write-LogTitle "Reset complet pile réseau"
        Run-Process 'ipconfig.exe' '/flushdns' -NoOutput
        Run-Process 'ipconfig.exe' '/release' -NoOutput
        Run-Process 'ipconfig.exe' '/renew' -NoOutput
        Run-Process 'netsh.exe' 'winsock reset'
        Run-Process 'netsh.exe' 'int ip reset'
        Run-Process 'netsh.exe' 'winhttp reset proxy'
        Run-Process 'netsh.exe' 'advfirewall reset'
        Write-Log "Reset complet terminé. Redémarrage recommandé." 'OK'
    }
}

# ----- Winget -----
function Op-WingetList {
    Wrap-Action {
        Write-LogTitle "Recherche des MAJ Winget"
        $where = (Get-Command winget -EA SilentlyContinue)
        if (-not $where) { Write-Log "Winget non détecté." 'ERROR'; return }
        $sync.UIQueue.Enqueue([pscustomobject]@{ Action='WingetClear' })
        Write-Log "Exécution : winget upgrade --include-unknown --accept-source-agreements"
        $output = & winget upgrade --include-unknown --accept-source-agreements 2>&1 | Out-String
        $lines = $output -split "`r?`n"
        $headerIdx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^Name\s+Id\s+Version\s+Available' -or $lines[$i] -match '^Nom\s+Id\s+Version\s+Disponible') {
                $headerIdx = $i; break
            }
        }
        if ($headerIdx -lt 0) { Write-Log "Aucune mise à jour disponible." 'OK'; $sync.UIQueue.Enqueue([pscustomobject]@{ Action='WingetCount'; Text='Aucune mise à jour disponible.' }); return }
        $headerLine = $lines[$headerIdx]
        # Calcul des positions de colonnes
        $colNames = @('Name','Id','Version','Available','Source')
        $positions = @()
        $cur = 0
        foreach ($cn in $colNames) {
            $found = $headerLine.IndexOf($cn, $cur, [StringComparison]::OrdinalIgnoreCase)
            if ($found -ge 0) { $positions += $found; $cur = $found + 1 } else { $positions += -1 }
        }
        # Si en français : Nom, Id, Version, Disponible, Source
        if ($positions[0] -lt 0) {
            $colNames = @('Nom','Id','Version','Disponible','Source')
            $positions = @()
            $cur = 0
            foreach ($cn in $colNames) {
                $found = $headerLine.IndexOf($cn, $cur, [StringComparison]::OrdinalIgnoreCase)
                if ($found -ge 0) { $positions += $found; $cur = $found + 1 } else { $positions += -1 }
            }
        }
        $count = 0
        for ($i = $headerIdx + 2; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if (-not $line -or $line.Trim() -eq '' -or $line.StartsWith('-')) { continue }
            if ($line -match '^\d+\s+(upgrades?|mises|packages)') { break }
            if ($line.Length -lt 10) { continue }
            try {
                $name = $line.Substring($positions[0], [Math]::Max(0, $positions[1] - $positions[0])).Trim()
                $id   = $line.Substring($positions[1], [Math]::Max(0, $positions[2] - $positions[1])).Trim()
                $ver  = $line.Substring($positions[2], [Math]::Max(0, $positions[3] - $positions[2])).Trim()
                $avail= $line.Substring($positions[3], [Math]::Max(0, $positions[4] - $positions[3])).Trim()
                $src  = if ($line.Length -gt $positions[4]) { $line.Substring($positions[4]).Trim() } else { '' }
                if ($id -and $name -and $name -notmatch 'No applicable upgrades') {
                    $obj = [pscustomobject]@{ Selected=$false; Name=$name; Id=$id; Version=$ver; Available=$avail; Source=$src }
                    $sync.UIQueue.Enqueue([pscustomobject]@{ Action='WingetAdd'; Item=$obj })
                    $count++
                }
            } catch {}
        }
        $sync.UIQueue.Enqueue([pscustomobject]@{ Action='WingetCount'; Text="$count mise(s) à jour disponible(s). Cochez celles à installer." })
        Write-Log "$count MAJ détectée(s)." 'OK'
    }
}
function Op-WingetUpdateSel {
    Wrap-Action {
        Write-LogTitle "Mise à jour sélective"
        $selected = @($sync.WingetUpgrades | Where-Object { $_.Selected })
        if ($selected.Count -eq 0) { Write-Log "Aucune sélection." 'WARN'; return }
        Write-Log "$($selected.Count) logiciel(s) à mettre à jour."
        foreach ($s in $selected) {
            if ($sync.CancelRequested) { Write-Log "Annulé." 'WARN'; return }
            Write-Log "→ MAJ $($s.Name) ($($s.Id))..."
            Run-Process 'winget.exe' "upgrade --id `"$($s.Id)`" --accept-source-agreements --accept-package-agreements --silent --include-unknown"
        }
        Write-Log "Mise à jour sélective terminée." 'OK'
    }
}
function Op-WingetUpdateAll {
    Wrap-Action {
        Write-LogTitle "Mise à jour de tous les logiciels"
        Run-Process 'winget.exe' 'upgrade --all --accept-source-agreements --accept-package-agreements --silent --include-unknown'
        Write-Log "Mise à jour terminée." 'OK'
    }
}
function Op-WingetListInstalled {
    Wrap-Action {
        Write-LogTitle "Logiciels installés (winget)"
        $sync.UIQueue.Enqueue([pscustomobject]@{ Action='InstalledClear' })
        $output = & winget list --accept-source-agreements 2>&1 | Out-String
        $lines = $output -split "`r?`n"
        $headerIdx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^Name\s+Id\s+Version' -or $lines[$i] -match '^Nom\s+Id\s+Version') { $headerIdx = $i; break }
        }
        if ($headerIdx -lt 0) { Write-Log "Sortie winget non parsable." 'WARN'; return }
        $headerLine = $lines[$headerIdx]
        $colNames = if ($headerLine -match '^Nom') { @('Nom','Id','Version','Available','Source') } else { @('Name','Id','Version','Available','Source') }
        $positions = @()
        $cur = 0
        foreach ($cn in $colNames) {
            $found = $headerLine.IndexOf($cn, $cur, [StringComparison]::OrdinalIgnoreCase)
            if ($found -ge 0) { $positions += $found; $cur = $found + 1 } else { $positions += -1 }
        }
        $count = 0
        for ($i = $headerIdx + 2; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if (-not $line -or $line.Trim() -eq '' -or $line.StartsWith('-')) { continue }
            if ($line.Length -lt 10) { continue }
            try {
                $name = $line.Substring($positions[0], [Math]::Max(0, $positions[1] - $positions[0])).Trim()
                $id   = $line.Substring($positions[1], [Math]::Max(0, $positions[2] - $positions[1])).Trim()
                $verEnd = if ($positions[3] -gt 0) { $positions[3] } else { $line.Length }
                $ver  = $line.Substring($positions[2], [Math]::Max(0, $verEnd - $positions[2])).Trim()
                $src  = if ($positions[4] -gt 0 -and $line.Length -gt $positions[4]) { $line.Substring($positions[4]).Trim() } else { '' }
                if ($id -and $name) {
                    $obj = [pscustomobject]@{ Selected=$false; Name=$name; Id=$id; Version=$ver; Source=$src }
                    $sync.UIQueue.Enqueue([pscustomobject]@{ Action='InstalledAdd'; Item=$obj })
                    $count++
                }
            } catch {}
        }
        $sync.UIQueue.Enqueue([pscustomobject]@{ Action='InstalledCount'; Text="$count logiciel(s) installé(s). Coche pour désinstaller." })
        Write-Log "$count logiciel(s) listé(s)." 'OK'
    }
}
function Op-WingetSearch {
    param([string]$Query)
    $sync.Arg1 = $Query
    Wrap-Action {
        $q = $sync.Arg1
        Write-LogTitle "Recherche Winget : $q"
        Run-Process 'winget.exe' "search --query `"$q`" --accept-source-agreements"
    }
}
function Op-WingetInstall {
    param([string]$Id)
    $sync.Arg1 = $Id
    Wrap-Action {
        $id = $sync.Arg1
        Write-LogTitle "Installation : $id"
        Run-Process 'winget.exe' "install --id `"$id`" --accept-source-agreements --accept-package-agreements"
    }
}
function Op-WingetUninstall {
    param([string]$Id)
    $sync.Arg1 = $Id
    Wrap-Action {
        $id = $sync.Arg1
        Write-LogTitle "Désinstallation : $id"
        Run-Process 'winget.exe' "uninstall --id `"$id`" --accept-source-agreements"
    }
}
function Op-WingetExport {
    param([string]$File)
    $sync.Arg1 = $File
    Wrap-Action {
        $f = $sync.Arg1
        Write-LogTitle "Export liste Winget"
        Run-Process 'winget.exe' "export --output `"$f`" --accept-source-agreements"
        Write-Log "Liste exportée → $f" 'OK'
    }
}
function Op-WingetImport {
    param([string]$File)
    $sync.Arg1 = $File
    Wrap-Action {
        $f = $sync.Arg1
        Write-LogTitle "Import liste Winget"
        Run-Process 'winget.exe' "import --import-file `"$f`" --accept-source-agreements --accept-package-agreements"
    }
}

# ----- Pilotes -----
function Op-DriversSearch {
    Wrap-Action {
        Write-LogTitle "Recherche de mises à jour de pilotes"
        $sync.UIQueue.Enqueue([pscustomobject]@{ Action='DriversClear' })
        $sync.DriverUpdatesCom = $null
        $sync.DriverFallbackMode = $false

        # Tentative 1 : Microsoft Update (inclut les drivers, contrairement à WSUS)
        try {
            $muServiceId = '7971f918-a847-4430-9279-4a52d1efe18d'
            $serviceManager = New-Object -ComObject Microsoft.Update.ServiceManager
            $muRegistered = $false
            foreach ($svc in $serviceManager.Services) {
                if ($svc.ServiceID -eq $muServiceId) { $muRegistered = $true; break }
            }
            if (-not $muRegistered) {
                Write-Log "Enregistrement du service Microsoft Update..."
                # Flags : 7 = AllowOnlineRegistration | AllowPendingRegistration | RegisterWithAU
                $null = $serviceManager.AddService2($muServiceId, 7, "")
            }
            $session = New-Object -ComObject Microsoft.Update.Session
            $searcher = $session.CreateUpdateSearcher()
            $searcher.ServerSelection = 3   # ssOthers
            $searcher.ServiceID = $muServiceId
            Write-Log "Interrogation Microsoft Update (cela peut prendre 1-3 minutes)..."
            $r = $searcher.Search("IsInstalled=0 and Type='Driver'")
            $sync.DriverUpdatesCom = $r.Updates
            $count = $r.Updates.Count
            if ($count -gt 0) {
                Write-Log "$count MAJ de pilote(s) détectée(s) via Microsoft Update :" 'OK'
                for ($i = 0; $i -lt $count; $i++) {
                    $u = $r.Updates.Item($i)
                    $size = if ($u.MaxDownloadSize) { '{0:N1} Mo' -f ($u.MaxDownloadSize / 1MB) } else { '?' }
                    $cat = ''
                    try { if ($u.Categories.Count -gt 0) { $cat = $u.Categories.Item(0).Name } } catch {}
                    $obj = [pscustomobject]@{
                        Selected = $false
                        Index = $i
                        Title = $u.Title
                        Category = $cat
                        Size = $size
                    }
                    $sync.UIQueue.Enqueue([pscustomobject]@{ Action='DriversAdd'; Item=$obj })
                    Write-Log "  • $($u.Title) ($size)"
                }
                $sync.UIQueue.Enqueue([pscustomobject]@{ Action='DriversCount'; Text="$count MAJ disponibles. Coche pour installer." })
                return
            } else {
                Write-Log "Aucune MAJ détectée via Microsoft Update — passage à l'inventaire local." 'WARN'
            }
        } catch {
            $hr = '0x{0:X8}' -f $_.Exception.HResult
            Write-Log "Microsoft Update indisponible (HRESULT $hr) : $($_.Exception.Message)" 'WARN'
            Write-Log "Bascule sur l'inventaire local des pilotes installés..." 'WARN'
        }

        # Tentative 2 : fallback inventaire des pilotes tiers via pnputil, trié par date
        try {
            $sync.DriverFallbackMode = $true
            Write-Log "Inventaire des pilotes tiers installés..."
            $output = & pnputil.exe /enum-drivers 2>&1 | Out-String
            $lines = $output -split "`r?`n"
            $allDrivers = @()
            $current = $null
            foreach ($line in $lines) {
                if ($line -match '^(Published Name|Nom publi[ée])\s*:\s*(.+)$') {
                    if ($current) { $allDrivers += $current }
                    $current = [ordered]@{ Published=$Matches[2].Trim(); Original=''; Provider=''; Class=''; Date=''; Version='' }
                } elseif ($current) {
                    if ($line -match '^(Original Name|Nom original|Nom de fichier d''origine)\s*:\s*(.+)$') { $current.Original = $Matches[2].Trim() }
                    elseif ($line -match '^(Provider Name|Fournisseur)\s*:\s*(.+)$') { $current.Provider = $Matches[2].Trim() }
                    elseif ($line -match '^(Class Name|Nom de classe|Classe)\s*:\s*(.+)$') { $current.Class = $Matches[2].Trim() }
                    elseif ($line -match '^(Driver Date|Date du pilote)\s*:\s*(.+)$') { $current.Date = $Matches[2].Trim() }
                    elseif ($line -match '^(Driver Version|Version du pilote)\s*:\s*(.+)$') { $current.Version = $Matches[2].Trim() }
                }
            }
            if ($current) { $allDrivers += $current }

            # Tri du plus ancien au plus récent (cibles probables de MAJ en haut)
            $sorted = $allDrivers | Sort-Object {
                try { [DateTime]::Parse($_.Date) } catch { [DateTime]::MaxValue }
            }
            $count = 0
            foreach ($d in $sorted) {
                $name = if ($d.Original) { $d.Original } else { $d.Published }
                $title = if ($d.Provider) { "$($d.Provider) — $name (v$($d.Version))" } else { "$name (v$($d.Version))" }
                $obj = [pscustomobject]@{
                    Selected = $false
                    Index = -1
                    Title = $title
                    Category = $d.Class
                    Size = $d.Date
                }
                $sync.UIQueue.Enqueue([pscustomobject]@{ Action='DriversAdd'; Item=$obj })
                $count++
            }
            $sync.UIQueue.Enqueue([pscustomobject]@{ Action='DriversCount'; Text="$count pilotes tiers — triés du plus ancien au plus récent (la colonne Taille affiche la date). Microsoft Update indisponible : vérifie manuellement chez le constructeur ou via Paramètres → Windows Update." })
            Write-Log "$count pilote(s) listé(s). Les plus anciens (potentiels candidats à MAJ) sont en haut." 'OK'
            Write-Log "Note : en mode inventaire, le bouton « Installer sélection » n'est pas opérationnel — la MAJ doit se faire via Settings ou le site du fabricant." 'WARN'
        } catch {
            Write-Log "Erreur d'inventaire pnputil : $($_.Exception.Message)" 'ERROR'
        }
    }
}
function Op-DriversInstallSel {
    Wrap-Action {
        Write-LogTitle "Installation des pilotes sélectionnés"
        if ($sync.DriverFallbackMode) {
            Write-Log "Mode inventaire : installation directe non disponible." 'WARN'
            Write-Log "Pour mettre à jour ces pilotes :" 'WARN'
            Write-Log "  • Paramètres Windows → Windows Update → Options avancées → Mises à jour facultatives → Pilotes" 'WARN'
            Write-Log "  • OU télécharge le pilote depuis le site du fabricant (NVIDIA, Intel, AMD, Realtek...)" 'WARN'
            return
        }
        if (-not $sync.DriverUpdatesCom) { Write-Log "Lance d'abord la recherche." 'WARN'; return }
        $selected = @($sync.DriverUpdates | Where-Object { $_.Selected })
        if ($selected.Count -eq 0) { Write-Log "Aucune sélection." 'WARN'; return }
        Write-Log "$($selected.Count) pilote(s) à installer."
        try {
            $coll = New-Object -ComObject Microsoft.Update.UpdateColl
            foreach ($s in $selected) {
                $u = $sync.DriverUpdatesCom.Item($s.Index)
                if (-not $u.EulaAccepted) { try { $u.AcceptEula() } catch {} }
                [void]$coll.Add($u)
            }
            $session = New-Object -ComObject Microsoft.Update.Session
            $downloader = $session.CreateUpdateDownloader()
            $downloader.Updates = $coll
            Write-Log "Téléchargement..."
            $downloader.Download() | Out-Null
            $installer = $session.CreateUpdateInstaller()
            $installer.Updates = $coll
            Write-Log "Installation..."
            $result = $installer.Install()
            $code = $result.ResultCode
            $codeStr = switch ($code) { 2 {'Réussi'} 3 {'Réussi avec erreurs'} 4 {'Échec'} 5 {'Annulé'} default {"Code $code"} }
            Write-Log "Résultat : $codeStr" 'OK'
            if ($result.RebootRequired) { Write-Log "Redémarrage requis pour finaliser." 'WARN' }
        } catch {
            Write-Log "Erreur d'installation : $($_.Exception.Message)" 'ERROR'
        }
    }
}
function Op-DriversList {
    Wrap-Action {
        Write-LogTitle "Liste des pilotes"
        Run-Process 'pnputil.exe' '/enum-drivers'
    }
}
function Op-DriversBackup {
    param([string]$Folder)
    $sync.Arg1 = $Folder
    Wrap-Action {
        $folder = $sync.Arg1
        Write-LogTitle "Sauvegarde des pilotes"
        if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
        Run-Process 'pnputil.exe' "/export-driver * `"$folder`""
        Write-Log "Pilotes sauvegardés dans : $folder" 'OK'
    }
}
function Op-DriversProblems {
    Wrap-Action {
        Write-LogTitle "Périphériques avec problèmes"
        $devs = Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne $null }
        if ($devs.Count -eq 0) { Write-Log "Aucun problème détecté." 'OK' }
        else {
            foreach ($d in $devs) { Write-Log "  ⚠ $($d.Caption) — code $($d.ConfigManagerErrorCode)" 'WARN' }
        }
    }
}
function Op-DriversUpdate { Wrap-Action { Start-Process 'ms-settings:windowsupdate'; Write-Log "Settings ouvert." 'OK' } }

# ----- Performances -----
function Op-PerfStartup {
    Wrap-Action {
        Write-LogTitle "Programmes au démarrage"
        $sync.UIQueue.Enqueue([pscustomobject]@{ Action='StartupClear' })
        $items = Get-CimInstance Win32_StartupCommand -EA SilentlyContinue
        $count = 0
        foreach ($i in $items) {
            $obj = [pscustomobject]@{
                Selected = $false
                Name = $i.Name
                Command = $i.Command
                Location = $i.Location
                User = $i.User
            }
            $sync.UIQueue.Enqueue([pscustomobject]@{ Action='StartupAdd'; Item=$obj })
            $count++
        }
        Write-Log "$count entrée(s) au démarrage listée(s)." 'OK'
    }
}
function Op-StartupDisable {
    Wrap-Action {
        Write-LogTitle "Désactivation des entrées de démarrage sélectionnées"
        $selected = @($sync.StartupItems | Where-Object { $_.Selected })
        if ($selected.Count -eq 0) { Write-Log "Aucune sélection." 'WARN'; return }
        foreach ($s in $selected) {
            Write-Log "→ $($s.Name) [$($s.Location)]"
            try {
                # Location est généralement HKLM\..\Run ou HKCU\..\Run
                if ($s.Location -match 'HK(LM|CU).*Run') {
                    $regPath = $s.Location -replace 'HKU\\\.DEFAULT','HKU:\.DEFAULT' `
                                          -replace '^HKLM','HKLM:' `
                                          -replace '^HKCU','HKCU:' `
                                          -replace '^HKU','HKU:'
                    if (Test-Path $regPath) {
                        Remove-ItemProperty -Path $regPath -Name $s.Name -Force -EA Stop
                        Write-Log "  ✓ Supprimé du registre" 'OK'
                    } else { Write-Log "  ✗ Chemin introuvable : $regPath" 'WARN' }
                } else {
                    Write-Log "  ✗ Source non gérée (probablement raccourci ou tâche planifiée)." 'WARN'
                }
            } catch { Write-Log "  ✗ $($_.Exception.Message)" 'WARN' }
        }
        Write-Log "Terminé. Relance « Lister » pour rafraîchir." 'OK'
    }
}
function Op-PerfServices {
    Wrap-Action {
        Write-LogTitle "Services Windows"
        $sync.UIQueue.Enqueue([pscustomobject]@{ Action='ServicesClear' })
        $svcs = Get-Service | Sort-Object DisplayName
        foreach ($s in $svcs) {
            $obj = [pscustomobject]@{
                Selected = $false
                Name = $s.Name
                DisplayName = $s.DisplayName
                Status = "$($s.Status)"
                StartType = "$($s.StartType)"
            }
            $sync.UIQueue.Enqueue([pscustomobject]@{ Action='ServicesAdd'; Item=$obj })
        }
        Write-Log "$($svcs.Count) services listés." 'OK'
    }
}
function Op-ServiceStop {
    Wrap-Action {
        Write-LogTitle "Arrêt des services sélectionnés"
        $selected = @($sync.ServicesItems | Where-Object { $_.Selected })
        if ($selected.Count -eq 0) { Write-Log "Aucune sélection." 'WARN'; return }
        foreach ($s in $selected) {
            Write-Log "→ Stop $($s.Name)"
            try { Stop-Service -Name $s.Name -Force -EA Stop; Write-Log "  ✓ Arrêté" 'OK' }
            catch { Write-Log "  ✗ $($_.Exception.Message)" 'WARN' }
        }
    }
}
function Op-ServiceStart {
    Wrap-Action {
        Write-LogTitle "Démarrage des services sélectionnés"
        $selected = @($sync.ServicesItems | Where-Object { $_.Selected })
        if ($selected.Count -eq 0) { Write-Log "Aucune sélection." 'WARN'; return }
        foreach ($s in $selected) {
            Write-Log "→ Start $($s.Name)"
            try { Start-Service -Name $s.Name -EA Stop; Write-Log "  ✓ Démarré" 'OK' }
            catch { Write-Log "  ✗ $($_.Exception.Message)" 'WARN' }
        }
    }
}
function Op-PerfTopProcs {
    Wrap-Action {
        Write-LogTitle "Top processus (CPU/RAM)"
        $sync.UIQueue.Enqueue([pscustomobject]@{ Action='ProcessesClear' })
        $procs = Get-Process | Sort-Object -Property @{Expression={$_.WorkingSet64};Descending=$true} | Select-Object -First 30
        foreach ($p in $procs) {
            $mem = [math]::Round($p.WorkingSet64 / 1MB, 1)
            $cpu = if ($p.CPU) { [math]::Round($p.CPU, 1) } else { 0 }
            $obj = [pscustomobject]@{
                Selected = $false
                Id = $p.Id
                Name = $p.ProcessName
                Cpu = $cpu
                Ram = $mem
            }
            $sync.UIQueue.Enqueue([pscustomobject]@{ Action='ProcessesAdd'; Item=$obj })
        }
        Write-Log "Top 30 processus listés (par RAM)." 'OK'
    }
}
function Op-ProcessKill {
    Wrap-Action {
        Write-LogTitle "Arrêt des processus sélectionnés"
        $selected = @($sync.ProcessesItems | Where-Object { $_.Selected })
        if ($selected.Count -eq 0) { Write-Log "Aucune sélection." 'WARN'; return }
        foreach ($p in $selected) {
            Write-Log "→ Kill PID $($p.Id) ($($p.Name))"
            try { Stop-Process -Id $p.Id -Force -EA Stop; Write-Log "  ✓ Tué" 'OK' }
            catch { Write-Log "  ✗ $($_.Exception.Message)" 'WARN' }
        }
    }
}
function Op-PerfPowerHigh {
    Wrap-Action {
        Write-LogTitle "Plan d'alimentation : Performances élevées"
        Run-Process 'powercfg.exe' '/setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        Write-Log "Plan activé (s'il existe)." 'OK'
    }
}
function Op-PerfPowerBalanced {
    Wrap-Action {
        Write-LogTitle "Plan d'alimentation : Équilibré"
        Run-Process 'powercfg.exe' '/setactive 381b4222-f694-41f0-9685-ff5bb260df2e'
        Write-Log "Plan équilibré activé." 'OK'
    }
}

# ----- Sécurité -----
function Op-DefStatus {
    Wrap-Action {
        Write-LogTitle "Statut Windows Defender"
        try {
            $s = Get-MpComputerStatus
            Write-Log "  Antivirus activé      : $($s.AntivirusEnabled)"
            Write-Log "  Protection temps réel : $($s.RealTimeProtectionEnabled)"
            Write-Log "  Signatures            : $($s.AntivirusSignatureVersion)"
            Write-Log "  Dernière MAJ          : $($s.AntivirusSignatureLastUpdated)"
            Write-Log "  Dernier scan rapide   : $($s.QuickScanEndTime)"
            Write-Log "  Dernier scan complet  : $($s.FullScanEndTime)"
        } catch { Write-Log "Erreur : $($_.Exception.Message)" 'ERROR' }
    }
}
function Op-DefUpdate {
    Wrap-Action {
        Write-LogTitle "MAJ signatures Defender"
        try { Update-MpSignature; Write-Log "Signatures à jour." 'OK' } catch { Write-Log $_.Exception.Message 'ERROR' }
    }
}
function Op-DefQuick {
    Wrap-Action {
        Write-LogTitle "Scan rapide Defender"
        try { Start-MpScan -ScanType QuickScan; Write-Log "Scan rapide terminé." 'OK' } catch { Write-Log $_.Exception.Message 'ERROR' }
    }
}
function Op-DefFull {
    Wrap-Action {
        Write-LogTitle "Scan complet Defender"
        Write-Log "Scan complet en cours, cela peut durer plusieurs heures..."
        try { Start-MpScan -ScanType FullScan; Write-Log "Scan complet terminé." 'OK' } catch { Write-Log $_.Exception.Message 'ERROR' }
    }
}
function Op-Mrt { Wrap-Action { Write-LogTitle "MRT"; Start-Process 'mrt.exe'; Write-Log "MRT lancé." 'OK' } }
function Op-Activation {
    Wrap-Action {
        Write-LogTitle "Statut activation Windows"
        Run-Process 'cscript.exe' "//nologo $env:windir\System32\slmgr.vbs /xpr"
        Run-Process 'cscript.exe' "//nologo $env:windir\System32\slmgr.vbs /dlv"
    }
}
function Op-HashFile {
    param([string]$Path)
    $sync.Arg1 = $Path
    Wrap-Action {
        $p = $sync.Arg1
        Write-LogTitle "Hash : $p"
        if (-not (Test-Path $p)) { Write-Log "Fichier introuvable." 'ERROR'; return }
        $md5 = (Get-FileHash -Algorithm MD5 -Path $p).Hash
        $sha1 = (Get-FileHash -Algorithm SHA1 -Path $p).Hash
        $sha256 = (Get-FileHash -Algorithm SHA256 -Path $p).Hash
        Write-Log "  MD5    : $md5"
        Write-Log "  SHA1   : $sha1"
        Write-Log "  SHA256 : $sha256"
        Write-Log "Hash calculés." 'OK'
    }
}

# ----- Récupération -----
function Op-RecCreatePoint {
    param([string]$Description)
    $sync.Arg1 = $Description
    Wrap-Action {
        $desc = $sync.Arg1
        Write-LogTitle "Création d'un point de restauration"
        try {
            Enable-ComputerRestore -Drive 'C:\' -EA SilentlyContinue
            Checkpoint-Computer -Description $desc -RestorePointType 'MODIFY_SETTINGS'
            Write-Log "Point créé : $desc" 'OK'
        } catch { Write-Log $_.Exception.Message 'ERROR' }
    }
}
function Op-RecListPoints {
    Wrap-Action {
        Write-LogTitle "Points de restauration"
        $pts = Get-ComputerRestorePoint -EA SilentlyContinue
        if (-not $pts) { Write-Log "Aucun point trouvé (ou Restore désactivé)." 'WARN'; return }
        foreach ($p in $pts) {
            $d = [Management.ManagementDateTimeConverter]::ToDateTime($p.CreationTime)
            Write-Log ("  #{0}  {1}  — {2}" -f $p.SequenceNumber, $d, $p.Description)
        }
    }
}
function Op-RecOpenRstrui { Wrap-Action { Start-Process 'rstrui.exe'; Write-Log "Restauration système ouverte." 'OK' } }
function Op-RecBcd {
    Wrap-Action {
        Write-LogTitle "Réparation BCD"
        Run-Process 'bootrec.exe' '/scanos'
        Run-Process 'bootrec.exe' '/fixmbr'
        Run-Process 'bootrec.exe' '/fixboot'
        Run-Process 'bootrec.exe' '/rebuildbcd'
    }
}

# ----- Infos système -----
function Op-InfoSummary {
    Wrap-Action {
        Write-LogTitle "Récapitulatif système"
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        $cpu = (Get-CimInstance Win32_Processor)[0]
        Write-Log "  Hostname     : $($cs.Name)"
        Write-Log "  OS           : $($os.Caption) $($os.Version) (build $($os.BuildNumber))"
        Write-Log "  Architecture : $($os.OSArchitecture)"
        Write-Log "  Constructeur : $($cs.Manufacturer) — $($cs.Model)"
        Write-Log "  CPU          : $($cpu.Name)"
        Write-Log "  Cœurs        : $($cpu.NumberOfCores) physiques / $($cpu.NumberOfLogicalProcessors) logiques"
        $ram = '{0:N1} Go' -f ($cs.TotalPhysicalMemory / 1GB)
        Write-Log "  RAM          : $ram"
        $up = (Get-Date) - $os.LastBootUpTime
        Write-Log "  Uptime       : $($up.Days)j $($up.Hours)h $($up.Minutes)m"
    }
}
function Op-InfoCpu { Wrap-Action { Write-LogTitle "CPU"; Get-CimInstance Win32_Processor | ForEach-Object { Write-Log "  $($_.Name)"; Write-Log "  Vitesse : $($_.MaxClockSpeed) MHz"; Write-Log "  Cœurs : $($_.NumberOfCores) phys / $($_.NumberOfLogicalProcessors) log" } } }
function Op-InfoRam {
    Wrap-Action {
        Write-LogTitle "RAM"
        $mods = Get-CimInstance Win32_PhysicalMemory
        $total = 0
        foreach ($m in $mods) {
            $total += $m.Capacity
            $cap = '{0:N1} Go' -f ($m.Capacity / 1GB)
            Write-Log "  Slot $($m.DeviceLocator) : $cap @ $($m.ConfiguredClockSpeed) MHz ($($m.Manufacturer) $($m.PartNumber))"
        }
        Write-Log ("  Total : {0:N1} Go" -f ($total / 1GB)) 'OK'
    }
}
function Op-InfoGpu {
    Wrap-Action {
        Write-LogTitle "GPU"
        Get-CimInstance Win32_VideoController | ForEach-Object {
            $vram = if ($_.AdapterRAM) { '{0:N1} Go' -f ($_.AdapterRAM / 1GB) } else { '?' }
            Write-Log "  $($_.Name) — VRAM $vram, driver $($_.DriverVersion)"
        }
    }
}
function Op-InfoDisks {
    Wrap-Action {
        Write-LogTitle "Disques"
        Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
            $tot = '{0:N1} Go' -f ($_.Size / 1GB)
            $free = '{0:N1} Go' -f ($_.FreeSpace / 1GB)
            $pct = if ($_.Size) { [Math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { 0 }
            Write-Log "  $($_.DeviceID) — $free libres / $tot ($pct% libre) — $($_.FileSystem)"
        }
    }
}
function Op-InfoSmart {
    Wrap-Action {
        Write-LogTitle "Santé disques (SMART)"
        try {
            $disks = Get-PhysicalDisk -EA SilentlyContinue
            foreach ($d in $disks) {
                Write-Log "  $($d.FriendlyName) [$($d.MediaType)] — Santé : $($d.HealthStatus) — Op : $($d.OperationalStatus)"
            }
        } catch { Write-Log "Get-PhysicalDisk indisponible." 'WARN' }
    }
}
function Op-InfoBattery {
    param([string]$Out)
    $sync.Arg1 = $Out
    Wrap-Action {
        $o = $sync.Arg1
        Write-LogTitle "Rapport batterie"
        Run-Process 'powercfg.exe' "/batteryreport /output `"$o`""
        Write-Log "Rapport généré : $o" 'OK'
        Start-Process $o
    }
}
function Op-InfoUptime {
    Wrap-Action {
        Write-LogTitle "Uptime"
        $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        $up = (Get-Date) - $boot
        Write-Log "  Démarré le : $boot"
        Write-Log "  Uptime     : $($up.Days)j $($up.Hours)h $($up.Minutes)m $($up.Seconds)s"
    }
}
function Op-InfoNet {
    Wrap-Action {
        Write-LogTitle "Adresses IP / MAC"
        Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
            $ip = (Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -EA SilentlyContinue).IPAddress -join ', '
            Write-Log "  $($_.Name) [$($_.MacAddress)]  → $ip"
        }
    }
}

# ----- Outils rapides -----
function Open-Tool {
    param([string]$Cmd, [string]$Args = '', [string]$Label)
    $sync.ToolCmd = $Cmd
    $sync.ToolArgs = $Args
    $sync.ToolLabel = $Label
    Wrap-Action {
        $c = $sync.ToolCmd; $a = $sync.ToolArgs; $l = $sync.ToolLabel
        Write-Log "Lancement : $l"
        if ($a) { Start-Process $c $a } else { Start-Process $c }
        Write-Log "$l ouvert." 'OK'
    }
}

# ----- Mots de passe WiFi -----
function Op-WifiPasswords {
    Wrap-Action {
        Write-LogTitle "Mots de passe WiFi sauvegardés"
        $output = & netsh wlan show profiles 2>&1 | Out-String
        $profiles = @()
        foreach ($line in ($output -split "`r?`n")) {
            if ($line -match ':\s*(.+?)\s*$' -and $line -notmatch 'Profils|Profiles') {
                $name = $Matches[1].Trim()
                if ($name -and $name -ne '' -and $name -notmatch '^[-=]+$') {
                    $profiles += $name
                }
            }
        }
        if ($profiles.Count -eq 0) { Write-Log "Aucun profil WiFi trouvé." 'WARN'; return }
        Write-Log "$($profiles.Count) profil(s) détecté(s)."
        $sync.WifiList = @()
        foreach ($p in $profiles) {
            $det = & netsh wlan show profile name="$p" key=clear 2>&1 | Out-String
            $key = ''
            if ($det -match 'Contenu de la cl[eé]\s*:\s*(.+)' -or $det -match 'Key Content\s*:\s*(.+)') {
                $key = $Matches[1].Trim()
            }
            $auth = ''
            if ($det -match 'Authentification\s*:\s*(.+)' -or $det -match 'Authentication\s*:\s*(.+)') {
                $auth = $Matches[1].Trim()
            }
            $sync.WifiList += [pscustomobject]@{ SSID=$p; Key=$key; Auth=$auth }
            if ($key) { Write-Log ("  • {0,-30} → {1} (auth: {2})" -f $p, $key, $auth) }
            else { Write-Log ("  • {0,-30} → (sans mot de passe ou indisponible)" -f $p) }
        }
        Write-Log "Pour exporter en CSV, utilise le bouton « Exporter WiFi »." 'OK'
    }
}
function Op-WifiExport {
    param([string]$File)
    $sync.Arg1 = $File
    Wrap-Action {
        $f = $sync.Arg1
        Write-LogTitle "Export WiFi → $f"
        if (-not $sync.WifiList -or $sync.WifiList.Count -eq 0) {
            Write-Log "Liste vide. Cliquez d'abord sur « Mots de passe WiFi »." 'WARN'
            return
        }
        $sync.WifiList | Export-Csv -Path $f -NoTypeInformation -Encoding UTF8
        Write-Log "$($sync.WifiList.Count) profil(s) exporté(s)." 'OK'
    }
}

# ----- Caches navigateurs -----
function Op-CleanBrowsers {
    Wrap-Action {
        Write-LogTitle "Nettoyage des caches navigateurs"
        $browsers = @(
            @{Name='Edge'; Process='msedge'; Path="$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"},
            @{Name='Chrome'; Process='chrome'; Path="$env:LOCALAPPDATA\Google\Chrome\User Data\Default"},
            @{Name='Brave'; Process='brave'; Path="$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default"},
            @{Name='Firefox'; Process='firefox'; Path="$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"}
        )
        $subfolders = 'Cache','Code Cache','GPUCache','Service Worker','ShaderCache'
        foreach ($b in $browsers) {
            if (-not (Test-Path $b.Path)) { Write-Log "  $($b.Name) : non installé."; continue }
            Write-Log "→ $($b.Name)"
            $p = Get-Process -Name $b.Process -EA SilentlyContinue
            if ($p) {
                Write-Log "  Fermeture de $($b.Process)..."
                $p | Stop-Process -Force -EA SilentlyContinue
                Start-Sleep -Milliseconds 600
            }
            if ($b.Name -eq 'Firefox') {
                # Firefox a une structure de profils différente : *.default-release/cache2
                Get-ChildItem -Path $b.Path -Directory -EA SilentlyContinue | ForEach-Object {
                    $cache = Join-Path $_.FullName 'cache2'
                    if (Test-Path $cache) {
                        try { Remove-Item "$cache\*" -Recurse -Force -EA Stop; Write-Log "  ✓ $($_.Name)\cache2 vidé" } catch { Write-Log "  ✗ $($_.Name)\cache2 partiellement vidé" 'WARN' }
                    }
                }
            } else {
                foreach ($s in $subfolders) {
                    $full = Join-Path $b.Path $s
                    if (Test-Path $full) {
                        try { Remove-Item "$full\*" -Recurse -Force -EA Stop; Write-Log "  ✓ $s vidé" } catch { Write-Log "  ✗ $s partiel" 'WARN' }
                    }
                }
            }
        }
        Write-Log "Caches navigateurs nettoyés." 'OK'
    }
}

# ----- Hibernation -----
function Op-HibernateOff {
    Wrap-Action {
        Write-LogTitle "Désactivation de l'hibernation"
        $hib = "$env:SystemDrive\hiberfil.sys"
        $sizeBefore = if (Test-Path $hib) { (Get-Item $hib -Force).Length } else { 0 }
        Write-Log ("hiberfil.sys avant : {0:N1} Go" -f ($sizeBefore / 1GB))
        Run-Process 'powercfg.exe' '/hibernate off'
        Write-Log "Hibernation désactivée — hiberfil.sys sera supprimé." 'OK'
    }
}
function Op-HibernateOn {
    Wrap-Action {
        Write-LogTitle "Activation de l'hibernation"
        Run-Process 'powercfg.exe' '/hibernate on'
        Write-Log "Hibernation activée." 'OK'
    }
}
function Op-HibernateStatus {
    Wrap-Action {
        Write-LogTitle "Statut hiberfil.sys"
        $hib = "$env:SystemDrive\hiberfil.sys"
        if (Test-Path $hib) {
            $size = (Get-Item $hib -Force).Length
            Write-Log ("hiberfil.sys : {0:N1} Go ({1} octets)" -f ($size / 1GB), $size)
            Write-Log "Hibernation : ACTIVÉE"
        } else {
            Write-Log "hiberfil.sys absent — hibernation : DÉSACTIVÉE"
        }
    }
}

# ----- File d'impression -----
function Op-PrintQueueClear {
    Wrap-Action {
        Write-LogTitle "Vidage de la file d'impression"
        Write-Log "Arrêt du service Spooler..."
        Run-Process 'net.exe' 'stop spooler' -NoOutput
        Start-Sleep -Milliseconds 500
        $spool = "$env:windir\System32\spool\PRINTERS"
        if (Test-Path $spool) {
            $count = 0
            Get-ChildItem -Path $spool -Force -EA SilentlyContinue | ForEach-Object {
                try { Remove-Item $_.FullName -Force -EA Stop; $count++ } catch {}
            }
            Write-Log "$count fichier(s) supprimé(s)." 'OK'
        } else {
            Write-Log "Dossier $spool introuvable." 'WARN'
        }
        Write-Log "Redémarrage du service Spooler..."
        Run-Process 'net.exe' 'start spooler' -NoOutput
        Write-Log "File d'impression vidée." 'OK'
    }
}

# ----- Télémétrie -----
function Op-TelemetryStatus {
    Wrap-Action {
        Write-LogTitle "Statut télémétrie Windows"
        $services = 'DiagTrack','dmwappushservice','WerSvc'
        foreach ($s in $services) {
            $sv = Get-Service -Name $s -EA SilentlyContinue
            if ($sv) {
                Write-Log ("  {0,-25} : {1} (StartType: {2})" -f $s, $sv.Status, $sv.StartType)
            } else {
                Write-Log ("  {0,-25} : non installé" -f $s)
            }
        }
        $key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
        if (Test-Path $key) {
            $v = (Get-ItemProperty -Path $key -Name AllowTelemetry -EA SilentlyContinue).AllowTelemetry
            Write-Log "  AllowTelemetry (policy) : $v"
        } else {
            Write-Log "  AllowTelemetry (policy) : non défini"
        }
    }
}
function Op-TelemetryOff {
    Wrap-Action {
        Write-LogTitle "Désactivation de la télémétrie"
        # Backup état actuel des services
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = Join-Path $sync.BackupDir "telemetry-state-$stamp.json"
        $state = @()
        $services = 'DiagTrack','dmwappushservice','WerSvc'
        foreach ($s in $services) {
            $sv = Get-Service -Name $s -EA SilentlyContinue
            if ($sv) { $state += @{ Name=$s; Status="$($sv.Status)"; StartType="$($sv.StartType)" } }
        }
        $state | ConvertTo-Json | Set-Content -Path $backup -Encoding UTF8
        Write-Log "État sauvegardé : $backup" 'OK'

        foreach ($s in $services) {
            $sv = Get-Service -Name $s -EA SilentlyContinue
            if ($sv) {
                if ($sv.Status -eq 'Running') {
                    try { Stop-Service -Name $s -Force -EA Stop; Write-Log "  ✓ $s arrêté" } catch { Write-Log "  ✗ $s : $($_.Exception.Message)" 'WARN' }
                }
                try { Set-Service -Name $s -StartupType Disabled -EA Stop; Write-Log "  ✓ $s désactivé" } catch { Write-Log "  ✗ $s startup : $($_.Exception.Message)" 'WARN' }
            }
        }
        # Tâches planifiées
        $tasks = @(
            'Microsoft\Windows\Application Experience\ProgramDataUpdater',
            'Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
            'Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
            'Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
            'Microsoft\Windows\Feedback\Siuf\DmClient'
        )
        foreach ($t in $tasks) {
            try { Disable-ScheduledTask -TaskPath ("\" + (Split-Path $t)) -TaskName (Split-Path $t -Leaf) -EA Stop | Out-Null; Write-Log "  ✓ Tâche désactivée : $(Split-Path $t -Leaf)" } catch {}
        }
        Write-Log "Télémétrie désactivée. Pour réactiver, utilisez « Réactiver la télémétrie »." 'OK'
    }
}
function Op-TelemetryOn {
    Wrap-Action {
        Write-LogTitle "Réactivation de la télémétrie"
        $services = @(
            @{Name='DiagTrack'; Type='Automatic'},
            @{Name='dmwappushservice'; Type='Manual'},
            @{Name='WerSvc'; Type='Manual'}
        )
        foreach ($s in $services) {
            $sv = Get-Service -Name $s.Name -EA SilentlyContinue
            if ($sv) {
                try { Set-Service -Name $s.Name -StartupType $s.Type -EA Stop; Write-Log "  ✓ $($s.Name) → $($s.Type)" } catch { Write-Log "  ✗ $($s.Name) : $($_.Exception.Message)" 'WARN' }
                try { Start-Service -Name $s.Name -EA Stop; Write-Log "  ✓ $($s.Name) démarré" } catch {}
            }
        }
        Write-Log "Télémétrie réactivée (réglages standards)." 'OK'
    }
}

# ----- BSOD -----
function Op-BsodList {
    Wrap-Action {
        Write-LogTitle "Derniers BSOD / crashes système"
        # Event log : BugCheck (1001), Kernel-Power 41 (unexpected shutdown)
        $events = $null
        try {
            $events = Get-WinEvent -FilterHashtable @{
                LogName='System'
                Id=1001,41,6008
                StartTime=(Get-Date).AddDays(-30)
            } -MaxEvents 30 -EA SilentlyContinue
        } catch {}
        if (-not $events -or $events.Count -eq 0) {
            Write-Log "Aucun crash récent dans l'event log (30 derniers jours)." 'OK'
        } else {
            Write-Log "$($events.Count) événement(s) suspects (30j) :" 'WARN'
            foreach ($e in $events) {
                $kind = switch ($e.Id) { 1001 {'BugCheck'} 41 {'Kernel-Power'} 6008 {'Unexpected shutdown'} default {"Id=$($e.Id)"} }
                Write-Log ("  [{0}] {1} : {2}" -f $e.TimeCreated.ToString('yyyy-MM-dd HH:mm'), $kind, ($e.Message -split "`n")[0].Trim())
            }
        }
        # Minidumps
        $minidir = "$env:windir\Minidump"
        if (Test-Path $minidir) {
            $dumps = Get-ChildItem -Path $minidir -Filter '*.dmp' -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 10
            if ($dumps) {
                Write-Log ""
                Write-Log "$($dumps.Count) minidump(s) récent(s) dans $minidir :" 'TITLE'
                foreach ($d in $dumps) {
                    $sz = '{0:N1} Mo' -f ($d.Length / 1MB)
                    Write-Log ("  • {0}  ({1})  — {2}" -f $d.Name, $sz, $d.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
                }
                Write-Log "Pour analyser : ouvrir avec WinDbg ou BlueScreenView (Nirsoft)."
            } else {
                Write-Log "Aucun minidump dans $minidir."
            }
        } else {
            Write-Log "Dossier minidump absent ($minidir)."
        }
    }
}
function Op-BsodMinidumpFolder {
    Wrap-Action {
        $dir = "$env:windir\Minidump"
        if (-not (Test-Path $dir)) { Write-Log "Dossier $dir absent." 'WARN'; return }
        Start-Process explorer.exe $dir
        Write-Log "Dossier ouvert : $dir" 'OK'
    }
}

# ----- Mode performances visuelles -----
function Op-VisualPerf {
    Wrap-Action {
        Write-LogTitle "Activation du mode Performances visuelles"
        # SystemPropertiesPerformance équivalent : VisualFXSetting=2 (best perf)
        $key = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        Set-ItemProperty -Path $key -Name 'VisualFXSetting' -Value 2 -Type DWord -Force
        # UserPreferencesMask : pas d'animation
        $up = 'HKCU:\Control Panel\Desktop'
        Set-ItemProperty -Path $up -Name 'UserPreferencesMask' -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -Type Binary -Force
        # Désactive l'animation des fenêtres
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Value '0' -Force -EA SilentlyContinue
        # DWM transparence/animations
        $dwm = 'HKCU:\SOFTWARE\Microsoft\Windows\DWM'
        if (Test-Path $dwm) {
            Set-ItemProperty -Path $dwm -Name 'EnableAeroPeek' -Value 0 -Type DWord -Force -EA SilentlyContinue
        }
        # Transparence Start Menu
        $perso = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        if (Test-Path $perso) {
            Set-ItemProperty -Path $perso -Name 'EnableTransparency' -Value 0 -Type DWord -Force -EA SilentlyContinue
        }
        Write-Log "Mode performances activé. Reconnexion ou redémarrage requis pour effet complet." 'OK'
    }
}
function Op-VisualBest {
    Wrap-Action {
        Write-LogTitle "Restauration des effets visuels par défaut"
        $key = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        Set-ItemProperty -Path $key -Name 'VisualFXSetting' -Value 0 -Type DWord -Force
        $up = 'HKCU:\Control Panel\Desktop'
        Set-ItemProperty -Path $up -Name 'UserPreferencesMask' -Value ([byte[]](0x9E,0x1E,0x07,0x80,0x12,0x00,0x00,0x00)) -Type Binary -Force
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Value '1' -Force -EA SilentlyContinue
        $perso = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        if (Test-Path $perso) {
            Set-ItemProperty -Path $perso -Name 'EnableTransparency' -Value 1 -Type DWord -Force -EA SilentlyContinue
        }
        Write-Log "Effets visuels par défaut restaurés." 'OK'
    }
}

# ----- Bloatware -----
function Op-BloatList {
    Wrap-Action {
        Write-LogTitle "Recherche du bloatware Windows"
        $sync.UIQueue.Enqueue([pscustomobject]@{ Action='BloatClear' })
        # Liste curée d'IDs de bloatware fréquent (préfixes d'AppxPackage Name)
        $bloatPatterns = @(
            'Microsoft.3DBuilder', 'Microsoft.BingFinance', 'Microsoft.BingNews', 'Microsoft.BingSports',
            'Microsoft.BingWeather', 'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.Microsoft3DViewer',
            'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.MixedReality.Portal',
            'Microsoft.NetworkSpeedTest', 'Microsoft.News', 'Microsoft.Office.Lens', 'Microsoft.Office.Sway',
            'Microsoft.OneConnect', 'Microsoft.People', 'Microsoft.Print3D', 'Microsoft.SkypeApp',
            'Microsoft.Wallet', 'Microsoft.WindowsAlarms', 'Microsoft.WindowsCamera', 'microsoft.windowscommunicationsapps',
            'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps', 'Microsoft.WindowsSoundRecorder',
            'Microsoft.Xbox.TCUI', 'Microsoft.XboxApp', 'Microsoft.XboxGameOverlay', 'Microsoft.XboxGamingOverlay',
            'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.YourPhone',
            'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'king.com.CandyCrushSaga', 'king.com.CandyCrushSodaSaga',
            '*.Twitter', '*.Facebook', '*.Netflix', '*.Spotify', '*.Disney', '*.TikTok',
            'Microsoft.MSPaint', 'Microsoft.MicrosoftStickyNotes', 'Clipchamp.Clipchamp'
        )
        $count = 0
        foreach ($pat in $bloatPatterns) {
            $pkgs = Get-AppxPackage -Name $pat -EA SilentlyContinue
            foreach ($pkg in $pkgs) {
                $obj = [pscustomobject]@{
                    Selected = $false
                    DisplayName = $pkg.Name
                    PackageFullName = $pkg.PackageFullName
                    Publisher = ($pkg.Publisher -replace 'CN=','').Split(',')[0]
                }
                $sync.UIQueue.Enqueue([pscustomobject]@{ Action='BloatAdd'; Item=$obj })
                $count++
            }
        }
        $sync.UIQueue.Enqueue([pscustomobject]@{ Action='BloatCount'; Text="$count package(s) détecté(s). Coche les paquets à désinstaller." })
        Write-Log "$count bloatware détecté(s)." 'OK'
    }
}
function Op-BloatRemove {
    Wrap-Action {
        Write-LogTitle "Désinstallation du bloatware sélectionné"
        $selected = @($sync.BloatList | Where-Object { $_.Selected })
        if ($selected.Count -eq 0) { Write-Log "Aucune sélection." 'WARN'; return }
        Write-Log "$($selected.Count) package(s) à désinstaller."
        foreach ($p in $selected) {
            if ($sync.CancelRequested) { Write-Log "Annulé." 'WARN'; return }
            Write-Log "→ $($p.DisplayName)"
            try {
                Get-AppxPackage -Name $p.DisplayName -EA SilentlyContinue | Remove-AppxPackage -EA Stop
                Write-Log "  ✓ Désinstallé"
            } catch {
                Write-Log "  ✗ Échec : $($_.Exception.Message)" 'WARN'
            }
        }
        Write-Log "Désinstallation terminée." 'OK'
    }
}

# ----- Profils de maintenance -----
function Op-ProfileWeekly {
    Wrap-Action {
        Write-LogTitle "Profil : Nettoyage hebdo"
        Write-Log "→ Vider %TEMP%"
        Get-ChildItem -Path $env:TEMP -Force -EA SilentlyContinue | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -EA Stop } catch {} }
        Write-Log "→ Vider Windows\Temp"
        Get-ChildItem -Path "$env:windir\Temp" -Force -EA SilentlyContinue | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -EA Stop } catch {} }
        Write-Log "→ Vider Prefetch"
        Get-ChildItem -Path "$env:windir\Prefetch" -Filter '*.pf' -Force -EA SilentlyContinue | ForEach-Object { try { Remove-Item $_.FullName -Force -EA Stop } catch {} }
        Write-Log "→ Flush DNS"
        Run-Process 'ipconfig.exe' '/flushdns' -NoOutput
        Write-Log "→ Vider corbeille"
        try { Clear-RecycleBin -Force -EA SilentlyContinue } catch {}
        Write-Log "Nettoyage hebdo terminé." 'OK'
    }
}
function Op-ProfileRepair {
    Wrap-Action {
        Write-LogTitle "Profil : Réparation système complète"
        Write-Log "1/4 — DISM CheckHealth"
        Run-Process 'dism.exe' '/Online /Cleanup-Image /CheckHealth'
        Write-Log "2/4 — DISM RestoreHealth"
        Run-Process 'dism.exe' '/Online /Cleanup-Image /RestoreHealth'
        Write-Log "3/4 — SFC /scannow"
        Run-Process 'sfc.exe' '/scannow'
        Write-Log "4/4 — Reset Windows Update"
        Run-Process 'net.exe' 'stop wuauserv' -NoOutput
        Get-ChildItem "$env:windir\SoftwareDistribution\*" -Force -EA SilentlyContinue | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -EA Stop } catch {} }
        Run-Process 'net.exe' 'start wuauserv' -NoOutput
        Write-Log "Réparation complète terminée." 'OK'
    }
}
function Op-ProfilePresale {
    Wrap-Action {
        Write-LogTitle "Profil : Avant vente PC"
        Write-Log "ATTENTION : opérations irréversibles à des fins de revente."
        Write-Log "→ Désinstallation du bloatware standard"
        $bloat = @('Microsoft.MicrosoftSolitaireCollection','Microsoft.GetHelp','Microsoft.Getstarted','*.Candy*','Microsoft.MixedReality.Portal','Microsoft.YourPhone','Microsoft.ZuneMusic','Microsoft.ZuneVideo')
        foreach ($p in $bloat) {
            try { Get-AppxPackage -Name $p -EA SilentlyContinue | Remove-AppxPackage -EA SilentlyContinue; Write-Log "  ✓ $p" } catch {}
        }
        Write-Log "→ Vider tous les caches utilisateur"
        Get-ChildItem -Path $env:TEMP -Force -EA SilentlyContinue | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -EA Stop } catch {} }
        Get-ChildItem -Path "$env:windir\Temp" -Force -EA SilentlyContinue | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -EA Stop } catch {} }
        Write-Log "→ Vider corbeille"
        try { Clear-RecycleBin -Force -EA SilentlyContinue } catch {}
        Write-Log "→ Reset DNS"
        Run-Process 'ipconfig.exe' '/flushdns' -NoOutput
        Write-Log "→ Création point de restauration"
        try {
            Enable-ComputerRestore -Drive 'C:\' -EA SilentlyContinue
            Checkpoint-Computer -Description "Avant vente PC ($(Get-Date -Format 'yyyy-MM-dd'))" -RestorePointType 'MODIFY_SETTINGS'
            Write-Log "  ✓ Point créé"
        } catch { Write-Log "  ✗ $($_.Exception.Message)" 'WARN' }
        Write-Log "Préparation avant vente terminée." 'OK'
    }
}

function Refresh-Profiles {
    try {
        if (-not $ctrl.ProfilesList) { return }
        $ctrl.ProfilesList.Items.Clear()
        if (-not (Test-Path $sync.ProfilesDir)) { return }
        Get-ChildItem -Path $sync.ProfilesDir -Filter '*.json' -EA SilentlyContinue | ForEach-Object {
            $ctrl.ProfilesList.Items.Add($_.BaseName) | Out-Null
        }
    } catch {
        try { Write-Log "Refresh-Profiles : $($_.Exception.Message)" 'WARN' } catch {}
    }
}

# ----- God Mode -----
function Op-GodMode {
    Wrap-Action {
        Write-LogTitle "Création du raccourci God Mode"
        $desktop = [Environment]::GetFolderPath('Desktop')
        $folder = Join-Path $desktop 'GodMode.{ED7BA470-8E54-465E-825C-99712043E01C}'
        if (Test-Path $folder) { Write-Log "Déjà présent : $folder" 'WARN'; return }
        try {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            Write-Log "GodMode créé sur le bureau : $folder" 'OK'
        } catch { Write-Log "Erreur : $($_.Exception.Message)" 'ERROR' }
    }
}

# ----- Dashboard -----
function Refresh-Dashboard {
  try {
    # Disque C:
    try {
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -EA SilentlyContinue
        if ($disk) {
            $freeGb = $disk.FreeSpace / 1GB
            $totalGb = $disk.Size / 1GB
            $pct = [Math]::Round(($disk.FreeSpace / $disk.Size) * 100, 0)
            $ctrl.CardDisk.Text = ('{0:N0} Go libres' -f $freeGb)
            $ctrl.CardDiskSub.Text = ('sur {0:N0} Go ({1}% libre)' -f $totalGb, $pct)
            $ctrl.CardDiskBar.Value = (100 - $pct)
            $rgb = if ($pct -lt 10) { @(0xFF,0x47,0x57) } elseif ($pct -lt 25) { @(0xFF,0xA9,0x40) } else { @(0x21,0xD0,0x7A) }
            $col = [System.Windows.Media.Color]::FromRgb([byte]$rgb[0], [byte]$rgb[1], [byte]$rgb[2])
            $ctrl.CardDiskBar.Foreground = New-Object System.Windows.Media.SolidColorBrush $col
        }
    } catch {}
    # Antivirus : Defender en priorité, sinon AV tiers via SecurityCenter2
    try {
        $defenderActive = $false
        $defenderSub = ''
        $mp = Get-MpComputerStatus -EA SilentlyContinue
        if ($mp -and $mp.AntivirusEnabled -and $mp.RealTimeProtectionEnabled) {
            $defenderActive = $true
            $age = if ($mp.AntivirusSignatureLastUpdated) { (New-TimeSpan -Start $mp.AntivirusSignatureLastUpdated -End (Get-Date)).Days } else { -1 }
            $defenderSub = if ($age -ge 0) { "Signatures : il y a $age jour(s)" } else { 'Signatures : ?' }
        }
        if ($defenderActive) {
            $ctrl.CardDefender.Text = 'Defender actif'
            $ctrl.CardDefender.Foreground = [System.Windows.Media.Brushes]::LightGreen
            $ctrl.CardDefenderSub.Text = $defenderSub
        } else {
            # Recherche d'un AV tiers via SecurityCenter2
            $av = $null
            try {
                $av = Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct -EA SilentlyContinue |
                      Where-Object { $_.displayName -and $_.displayName -notmatch 'Windows Defender' } |
                      Select-Object -First 1
            } catch {}
            if (-not $av) {
                # Fallback : prend même Defender si présent (état désactivé)
                try {
                    $av = Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct -EA SilentlyContinue | Select-Object -First 1
                } catch {}
            }
            if ($av) {
                # productState bitfield : byte[1] (0x10 = on, 0x00 = off), byte[2] (0x00 = up-to-date, 0x10 = outdated)
                $state = [int]$av.productState
                $enabled = (($state -band 0x1000) -ne 0) -or (($state -band 0x10) -ne 0)
                $upToDate = ($state -band 0x10) -eq 0 -or (($state -shr 16) -band 0x10) -eq 0
                $ctrl.CardDefender.Text = $av.displayName
                if ($enabled) {
                    $ctrl.CardDefender.Foreground = [System.Windows.Media.Brushes]::LightGreen
                    $sub = 'Tiers détecté'
                    if (-not $upToDate) { $sub = 'Tiers — signatures à jour à vérifier' }
                    $ctrl.CardDefenderSub.Text = $sub
                } else {
                    $ctrl.CardDefender.Foreground = [System.Windows.Media.Brushes]::OrangeRed
                    $ctrl.CardDefenderSub.Text = 'Tiers — désactivé'
                }
            } else {
                $ctrl.CardDefender.Text = 'Aucun AV'
                $ctrl.CardDefender.Foreground = [System.Windows.Media.Brushes]::OrangeRed
                $ctrl.CardDefenderSub.Text = 'Aucune protection détectée'
            }
        }
    } catch {}
    # MAJ Windows en attente (rapide via COM, peut être lent — on le fait async)
    $ctrl.CardUpdates.Text = '...'
    $ctrl.CardUpdatesSub.Text = 'Recherche en cours'
    # RAM
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $totalMb = $os.TotalVisibleMemorySize / 1024
        $freeMb = $os.FreePhysicalMemory / 1024
        $usedMb = $totalMb - $freeMb
        $pctUsed = [Math]::Round(($usedMb / $totalMb) * 100, 0)
        $ctrl.CardRam.Text = ('{0:N1} / {1:N1} Go' -f ($usedMb/1024), ($totalMb/1024))
        $ctrl.CardRamSub.Text = "$pctUsed% utilisée"
        $ctrl.CardRamBar.Value = $pctUsed
    } catch {}
    # BSOD
    try {
        $bsod = Get-WinEvent -FilterHashtable @{LogName='System'; Id=1001,41; StartTime=(Get-Date).AddDays(-30)} -MaxEvents 50 -EA SilentlyContinue
        $n = if ($bsod) { @($bsod).Count } else { 0 }
        $ctrl.CardBsod.Text = "$n"
        if ($n -eq 0) {
            $ctrl.CardBsod.Foreground = [System.Windows.Media.Brushes]::LightGreen
            $ctrl.CardBsodSub.Text = 'Aucun crash récent'
        } else {
            $ctrl.CardBsod.Foreground = [System.Windows.Media.Brushes]::OrangeRed
            $ctrl.CardBsodSub.Text = "événement(s) suspect(s)"
        }
    } catch {
        $ctrl.CardBsod.Text = '?'
        $ctrl.CardBsodSub.Text = ''
    }
    # Uptime + dernier point de restauration
    try {
        $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        $up = (Get-Date) - $boot
        $ctrl.CardUptime.Text = ('{0}j {1}h {2}m' -f $up.Days, $up.Hours, $up.Minutes)
        $rp = Get-ComputerRestorePoint -EA SilentlyContinue | Sort-Object SequenceNumber -Descending | Select-Object -First 1
        if ($rp) {
            $rd = [Management.ManagementDateTimeConverter]::ToDateTime($rp.CreationTime)
            $ctrl.CardRestore.Text = "Restore : $($rd.ToString('yyyy-MM-dd'))"
        } else {
            $ctrl.CardRestore.Text = 'Aucun point de restauration'
        }
    } catch {}
    # MAJ Windows : indicateur statique. La recherche COM en sous-runspace
    # cause des erreurs cross-thread WPF+PS. Le bouton « Lister MAJ en attente »
    # de la catégorie Windows Update fait l'analyse complète quand l'utilisateur le demande.
    $ctrl.CardUpdates.Text = '—'
    $ctrl.CardUpdatesSub.Text = 'Voir « Windows Update »'
  } catch {
    try { Write-Log "Refresh-Dashboard : $($_.Exception.Message)" 'WARN' } catch {}
  }
}
#endregion

#region Bindings boutons

# Réparation
$ctrl.BtnSFC.Add_Click({         Invoke-Async (Op-SFC) 'SFC en cours...' })
$ctrl.BtnDismCheck.Add_Click({   Invoke-Async (Op-DismCheck) 'DISM CheckHealth...' })
$ctrl.BtnDismScan.Add_Click({    Invoke-Async (Op-DismScan) 'DISM ScanHealth...' })
$ctrl.BtnDismRestore.Add_Click({ Invoke-Async (Op-DismRestore) 'DISM RestoreHealth...' })
$ctrl.BtnDismAnalyze.Add_Click({ Invoke-Async (Op-DismAnalyze) 'DISM Analyze...' })
$ctrl.BtnFullRepair.Add_Click({
    if (Confirm-Action "Lancer la réparation complète (SFC + DISM) ? Cela peut durer 30+ minutes.") {
        Invoke-Async (Op-FullRepair) 'Réparation complète...'
    }
})
$ctrl.BtnReregisterDLLs.Add_Click({ Invoke-Async (Op-ReregisterDLLs) 'Réenregistrement DLLs...' })
$ctrl.BtnWmi.Add_Click({          Invoke-Async (Op-Wmi) 'Vérification WMI...' })
$ctrl.BtnChkdsk.Add_Click({
    if (Confirm-Action "Planifier CHKDSK C: /F /R au prochain redémarrage ?") {
        Invoke-Async (Op-Chkdsk) 'Planification CHKDSK...'
    }
})
$ctrl.BtnBcd.Add_Click({
    if (Confirm-Action "Réparer le BCD ? Ceci modifie le secteur de démarrage.") {
        Invoke-Async (Op-Bcd) 'Réparation BCD...'
    }
})

# Windows Update
$ctrl.BtnWuReset.Add_Click({
    if (Confirm-Action "Réinitialiser Windows Update ? Les services seront stoppés et les caches supprimés.") {
        Invoke-Async (Op-WuReset) 'Reset Windows Update...'
    }
})
$ctrl.BtnWuOpen.Add_Click({       Invoke-Async (Op-WuOpen) 'Ouverture...' })
$ctrl.BtnWuHistory.Add_Click({    Invoke-Async (Op-WuHistory) 'Historique...' })
$ctrl.BtnWuPending.Add_Click({    Invoke-Async (Op-WuPending) 'Recherche...' })

# Nettoyage
$ctrl.BtnCleanUserTemp.Add_Click({ if (Confirm-Action "Vider le dossier %TEMP% utilisateur ?") { Invoke-Async (Op-CleanUserTemp) 'Nettoyage...' } })
$ctrl.BtnCleanWinTemp.Add_Click({  if (Confirm-Action "Vider C:\Windows\Temp ?") { Invoke-Async (Op-CleanWinTemp) 'Nettoyage...' } })
$ctrl.BtnCleanPrefetch.Add_Click({ if (Confirm-Action "Vider Prefetch ? Le premier démarrage des apps sera plus lent.") { Invoke-Async (Op-CleanPrefetch) 'Nettoyage...' } })
$ctrl.BtnCleanThumbs.Add_Click({   if (Confirm-Action "Vider le cache des miniatures ? Explorer va redémarrer.") { Invoke-Async (Op-CleanThumbs) 'Nettoyage...' } })
$ctrl.BtnCleanRecycle.Add_Click({  if (Confirm-Action "Vider la corbeille ?") { Invoke-Async (Op-CleanRecycle) 'Nettoyage...' } })
$ctrl.BtnCleanSWD.Add_Click({      if (Confirm-Action "Vider SoftwareDistribution ?") { Invoke-Async (Op-CleanSWD) 'Nettoyage...' } })
$ctrl.BtnCleanCatroot.Add_Click({  if (Confirm-Action "Vider catroot2 ?") { Invoke-Async (Op-CleanCatroot) 'Nettoyage...' } })
$ctrl.BtnCleanDeliveryOpt.Add_Click({ if (Confirm-Action "Vider le cache Delivery Optimization ?") { Invoke-Async (Op-CleanDeliveryOpt) 'Nettoyage...' } })
$ctrl.BtnCleanmgr.Add_Click({      Invoke-Async (Op-CleanmgrSimple) 'Disk Cleanup...' })
$ctrl.BtnCleanmgrSage.Add_Click({  Invoke-Async (Op-CleanmgrSage) 'Disk Cleanup étendu...' })
$ctrl.BtnCleanWinOld.Add_Click({   if (Confirm-Action "Supprimer Windows.old ? Tu ne pourras plus revenir à l'ancienne version de Windows." 'Action irréversible') { Invoke-Async (Op-CleanWinOld) 'Suppression Windows.old...' } })
$ctrl.BtnCleanAll.Add_Click({      if (Confirm-Action "Effectuer un nettoyage complet ? Tous les caches temporaires seront vidés.") { Invoke-Async (Op-CleanAll) 'Nettoyage complet...' } })

# Registre
$ctrl.BtnRegBackup.Add_Click({     Invoke-Async (Op-RegBackup) 'Sauvegarde registre...' })
$ctrl.BtnRegOpenBackups.Add_Click({Invoke-Async (Op-RegOpenBackups) '...' })
$ctrl.BtnRegScanUninstall.Add_Click({ Invoke-Async (Op-RegScanUninstall) 'Analyse...' })
$ctrl.BtnRegScanStartup.Add_Click({   Invoke-Async (Op-RegScanStartup) 'Analyse...' })
$ctrl.BtnRegMUICache.Add_Click({
    if (Confirm-Action "Nettoyer MUICache ? Backup auto effectué d'abord.") {
        $sync.ConfirmedMuiCache = $true
        # Backup auto avant
        Invoke-Async (Wrap-Action {
            Write-LogTitle "Backup HKCU avant nettoyage MUICache"
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $f = Join-Path $sync.BackupDir "registry-MUICache-$stamp.reg"
            Run-Process 'reg.exe' "export `"HKCU\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache`" `"$f`" /y" -NoOutput
            Write-Log "Backup → $f" 'OK'
            Write-LogTitle "Nettoyage MUICache"
            $key = 'HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'
            if (-not (Test-Path $key)) { Write-Log "Introuvable." 'WARN'; return }
            $count = 0
            $r = Get-Item $key
            foreach ($n in $r.Property) {
                try {
                    $exe = ($n -split '\.')[0]
                    if (Test-Path $exe -PathType Leaf) { continue }
                    Remove-ItemProperty -Path $key -Name $n -ErrorAction Stop
                    $count++
                } catch {}
            }
            Write-Log "$count entrée(s) supprimée(s)." 'OK'
        }) 'Nettoyage MUICache...'
    }
})
$ctrl.BtnRegRecentDocs.Add_Click({
    if (Confirm-Action "Vider la liste des documents récents ?") {
        Invoke-Async (Op-RegRecentDocs) 'Nettoyage RecentDocs...'
    }
})
$ctrl.BtnRegCompact.Add_Click({   Invoke-Async (Op-RegCompact) '...' })

# Réseau
$ctrl.BtnNetIpconfig.Add_Click({  Invoke-Async (Op-NetIpconfig) 'Lecture config IP...' })
$ctrl.BtnNetFlushDns.Add_Click({  Invoke-Async (Op-NetFlushDns) 'Flush DNS...' })
$ctrl.BtnNetReleaseRenew.Add_Click({ if (Confirm-Action "Release/Renew IP ? Brève coupure réseau.") { Invoke-Async (Op-NetReleaseRenew) 'Release/Renew...' } })
$ctrl.BtnNetPing.Add_Click({      Invoke-Async (Op-NetPing) 'Ping...' })
$ctrl.BtnNetTrace.Add_Click({     Invoke-Async (Op-NetTrace) 'Traceroute...' })
$ctrl.BtnNetWinsock.Add_Click({   if (Confirm-Action "Reset Winsock ? Redémarrage requis.") { Invoke-Async (Op-NetWinsock) 'Reset Winsock...' } })
$ctrl.BtnNetTcpip.Add_Click({     if (Confirm-Action "Reset TCP/IP ? Redémarrage requis.") { Invoke-Async (Op-NetTcpip) 'Reset TCP/IP...' } })
$ctrl.BtnNetProxy.Add_Click({     Invoke-Async (Op-NetProxy) 'Reset proxy...' })
$ctrl.BtnNetHosts.Add_Click({     if (Confirm-Action "Réinitialiser le fichier hosts ? Backup automatique avant.") { Invoke-Async (Op-NetHosts) 'Reset hosts...' } })
$ctrl.BtnNetAll.Add_Click({       if (Confirm-Action "Reset complet de la pile réseau ? Redémarrage requis." 'Action sensible') { Invoke-Async (Op-NetAll) 'Reset réseau...' } })

# Winget
$ctrl.BtnWingetList.Add_Click({          Invoke-Async (Op-WingetList) 'Recherche MAJ Winget...' })
$ctrl.BtnWingetUpdateSel.Add_Click({
    $sel = @($sync.WingetUpgrades | Where-Object { $_.Selected })
    if ($sel.Count -eq 0) { Show-Warning "Coche au moins un logiciel à mettre à jour."; return }
    if (Confirm-Action "Mettre à jour les $($sel.Count) logiciel(s) sélectionné(s) ?") {
        Invoke-Async (Op-WingetUpdateSel) 'MAJ sélection...'
    }
})
$ctrl.BtnWingetUpdateAll.Add_Click({
    if (Confirm-Action "Mettre à jour TOUS les logiciels installés via winget ? Cela peut redémarrer certaines applications.") {
        Invoke-Async (Op-WingetUpdateAll) 'MAJ tous logiciels...'
    }
})
$ctrl.BtnWingetListInstalled.Add_Click({ Invoke-Async (Op-WingetListInstalled) 'Liste installés...' })
$ctrl.BtnWingetSearch.Add_Click({
    $q = Prompt-Text "Rechercher un logiciel (ex : firefox, vlc, vscode) :" "Winget Search"
    if ($q) { Invoke-Async (Op-WingetSearch -Query $q) "Recherche $q..." }
})
$ctrl.BtnWingetInstall.Add_Click({
    $id = Prompt-Text "ID exact du logiciel à installer (ex : Mozilla.Firefox) :" "Winget Install"
    if ($id) {
        if (Confirm-Action "Installer $id ?") { Invoke-Async (Op-WingetInstall -Id $id) "Installation..." }
    }
})
$ctrl.BtnWingetUninstallSel.Add_Click({
    $sel = @($sync.WingetInstalled | Where-Object { $_.Selected })
    if ($sel.Count -eq 0) { Show-Warning "Coche au moins un logiciel à désinstaller dans la liste."; return }
    if (Confirm-Action "Désinstaller les $($sel.Count) logiciel(s) sélectionné(s) ?") {
        $sync.UninstallList = @($sel | ForEach-Object { $_.Id })
        Invoke-Async (Wrap-Action {
            Write-LogTitle "Désinstallation sélective"
            foreach ($id in $sync.UninstallList) {
                if ($sync.CancelRequested) { Write-Log "Annulé." 'WARN'; return }
                Write-Log "→ Désinstallation : $id"
                Run-Process 'winget.exe' "uninstall --id `"$id`" --silent --accept-source-agreements"
            }
            Write-Log "Désinstallation terminée." 'OK'
        }) "Désinstallation..."
    }
})
$ctrl.BtnWingetExport.Add_Click({
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = 'JSON|*.json'
    $sfd.FileName = "winget-export-$(Get-Date -Format 'yyyyMMdd').json"
    if ($sfd.ShowDialog() -eq 'OK') { Invoke-Async (Op-WingetExport -File $sfd.FileName) 'Export...' }
})
$ctrl.BtnWingetImport.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = 'JSON|*.json'
    if ($ofd.ShowDialog() -eq 'OK') {
        if (Confirm-Action "Importer la liste depuis $($ofd.FileName) et installer tous les logiciels ?") {
            Invoke-Async (Op-WingetImport -File $ofd.FileName) 'Import...'
        }
    }
})

# Pilotes
$ctrl.BtnDriversSearch.Add_Click({   Invoke-Async (Op-DriversSearch) 'Recherche MAJ pilotes...' })
$ctrl.BtnDriversInstallSel.Add_Click({
    $sel = @($sync.DriverUpdates | Where-Object { $_.Selected })
    if ($sel.Count -eq 0) { Show-Warning "Coche au moins un pilote à installer."; return }
    if (Confirm-Action "Installer les $($sel.Count) pilote(s) sélectionné(s) ? Un redémarrage peut être nécessaire.") {
        Invoke-Async (Op-DriversInstallSel) 'Installation pilotes...'
    }
})
$ctrl.BtnDriversList.Add_Click({     Invoke-Async (Op-DriversList) 'Liste pilotes...' })
$ctrl.BtnDriversBackup.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Dossier de sauvegarde des pilotes"
    if ($fbd.ShowDialog() -eq 'OK') { Invoke-Async (Op-DriversBackup -Folder $fbd.SelectedPath) 'Backup pilotes...' }
})
$ctrl.BtnDriversProblems.Add_Click({ Invoke-Async (Op-DriversProblems) 'Analyse...' })
$ctrl.BtnDriversUpdate.Add_Click({   Invoke-Async (Op-DriversUpdate) '...' })

# Performances
$ctrl.BtnPerfStartup.Add_Click({       Invoke-Async (Op-PerfStartup) 'Liste démarrage...' })
$ctrl.BtnStartupDisable.Add_Click({
    $sel = @($sync.StartupItems | Where-Object { $_.Selected })
    if ($sel.Count -eq 0) { Show-Warning "Coche au moins une entrée à désactiver."; return }
    if (Confirm-Action "Désactiver les $($sel.Count) entrée(s) ? Suppression du registre.") {
        Invoke-Async (Op-StartupDisable) 'Désactivation démarrage...'
    }
})
$ctrl.BtnPerfServices.Add_Click({      Invoke-Async (Op-PerfServices) 'Liste services...' })
$ctrl.BtnServiceStop.Add_Click({
    $sel = @($sync.ServicesItems | Where-Object { $_.Selected })
    if ($sel.Count -eq 0) { Show-Warning "Coche au moins un service."; return }
    if (Confirm-Action "Arrêter les $($sel.Count) service(s) ?") { Invoke-Async (Op-ServiceStop) 'Arrêt services...' }
})
$ctrl.BtnServiceStart.Add_Click({
    $sel = @($sync.ServicesItems | Where-Object { $_.Selected })
    if ($sel.Count -eq 0) { Show-Warning "Coche au moins un service."; return }
    Invoke-Async (Op-ServiceStart) 'Démarrage services...'
})
$ctrl.BtnPerfTopProcs.Add_Click({      Invoke-Async (Op-PerfTopProcs) 'Top processus...' })
$ctrl.BtnProcessKill.Add_Click({
    $sel = @($sync.ProcessesItems | Where-Object { $_.Selected })
    if ($sel.Count -eq 0) { Show-Warning "Coche au moins un processus."; return }
    if (Confirm-Action "Tuer les $($sel.Count) processus sélectionné(s) ? Données non sauvegardées seront perdues.") {
        Invoke-Async (Op-ProcessKill) 'Kill processus...'
    }
})
$ctrl.BtnPerfPowerHigh.Add_Click({     Invoke-Async (Op-PerfPowerHigh) "Plan d'alim..." })
$ctrl.BtnPerfPowerBalanced.Add_Click({ Invoke-Async (Op-PerfPowerBalanced) "Plan d'alim..." })

# Sécurité
$ctrl.BtnDefStatus.Add_Click({ Invoke-Async (Op-DefStatus) 'Statut Defender...' })
$ctrl.BtnDefUpdate.Add_Click({ Invoke-Async (Op-DefUpdate) 'MAJ Defender...' })
$ctrl.BtnDefQuick.Add_Click({  if (Confirm-Action "Lancer un scan rapide Defender ?") { Invoke-Async (Op-DefQuick) 'Scan rapide...' } })
$ctrl.BtnDefFull.Add_Click({   if (Confirm-Action "Lancer un scan complet Defender ? Plusieurs heures.") { Invoke-Async (Op-DefFull) 'Scan complet...' } })
$ctrl.BtnMrt.Add_Click({       Invoke-Async (Op-Mrt) 'MRT...' })
$ctrl.BtnActivation.Add_Click({Invoke-Async (Op-Activation) 'Activation...' })
$ctrl.BtnHashFile.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    if ($ofd.ShowDialog() -eq 'OK') { Invoke-Async (Op-HashFile -Path $ofd.FileName) 'Hash...' }
})

# Récupération
$ctrl.BtnRecCreatePoint.Add_Click({
    $desc = Prompt-Text "Description du point de restauration :" "Point de restauration" "Titalium - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    if ($desc) { Invoke-Async (Op-RecCreatePoint -Description $desc) 'Création point...' }
})
$ctrl.BtnRecListPoints.Add_Click({  Invoke-Async (Op-RecListPoints) 'Liste points...' })
$ctrl.BtnRecOpenRstrui.Add_Click({  Invoke-Async (Op-RecOpenRstrui) '...' })
$ctrl.BtnRecBcd.Add_Click({         if (Confirm-Action "Réparer le boot (BCD) ?") { Invoke-Async (Op-RecBcd) 'Réparation BCD...' } })

# Infos
$ctrl.BtnInfoSummary.Add_Click({   Invoke-Async (Op-InfoSummary) 'Récap...' })
$ctrl.BtnInfoCpu.Add_Click({       Invoke-Async (Op-InfoCpu) 'CPU...' })
$ctrl.BtnInfoRam.Add_Click({       Invoke-Async (Op-InfoRam) 'RAM...' })
$ctrl.BtnInfoGpu.Add_Click({       Invoke-Async (Op-InfoGpu) 'GPU...' })
$ctrl.BtnInfoDisks.Add_Click({     Invoke-Async (Op-InfoDisks) 'Disques...' })
$ctrl.BtnInfoSmart.Add_Click({     Invoke-Async (Op-InfoSmart) 'SMART...' })
$ctrl.BtnInfoBattery.Add_Click({
    $out = Join-Path $sync.LogDir "battery-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
    Invoke-Async (Op-InfoBattery -Out $out) 'Rapport batterie...'
})
$ctrl.BtnInfoUptime.Add_Click({    Invoke-Async (Op-InfoUptime) 'Uptime...' })
$ctrl.BtnInfoNet.Add_Click({       Invoke-Async (Op-InfoNet) 'Réseau...' })

# Outils rapides
$ctrl.BtnToolRegedit.Add_Click({   Invoke-Async (Open-Tool -Cmd 'regedit.exe' -Label 'Éditeur de registre') 'Lancement...' })
$ctrl.BtnToolServices.Add_Click({  Invoke-Async (Open-Tool -Cmd 'services.msc' -Label 'Services') 'Lancement...' })
$ctrl.BtnToolDevmgmt.Add_Click({   Invoke-Async (Open-Tool -Cmd 'devmgmt.msc' -Label 'Périphériques') 'Lancement...' })
$ctrl.BtnToolEventvwr.Add_Click({  Invoke-Async (Open-Tool -Cmd 'eventvwr.msc' -Label "Observateur d'événements") 'Lancement...' })
$ctrl.BtnToolTaskmgr.Add_Click({   Invoke-Async (Open-Tool -Cmd 'taskmgr.exe' -Label 'Gestionnaire des tâches') 'Lancement...' })
$ctrl.BtnToolDiskmgmt.Add_Click({  Invoke-Async (Open-Tool -Cmd 'diskmgmt.msc' -Label 'Gestion des disques') 'Lancement...' })
$ctrl.BtnToolMsconfig.Add_Click({  Invoke-Async (Open-Tool -Cmd 'msconfig.exe' -Label 'msconfig') 'Lancement...' })
$ctrl.BtnToolMsinfo.Add_Click({    Invoke-Async (Open-Tool -Cmd 'msinfo32.exe' -Label 'Informations système') 'Lancement...' })
$ctrl.BtnToolPerfmon.Add_Click({   Invoke-Async (Open-Tool -Cmd 'perfmon.exe' -Label 'Moniteur de performances') 'Lancement...' })
$ctrl.BtnToolResmon.Add_Click({    Invoke-Async (Open-Tool -Cmd 'resmon.exe' -Label 'Moniteur de ressources') 'Lancement...' })
$ctrl.BtnToolControl.Add_Click({   Invoke-Async (Open-Tool -Cmd 'control.exe' -Label 'Panneau de configuration') 'Lancement...' })
$ctrl.BtnToolSettings.Add_Click({  Invoke-Async (Open-Tool -Cmd 'ms-settings:' -Label 'Paramètres') 'Lancement...' })

# Footer Hyperlink → titalium.fr
$ctrl.LinkTitalium.Add_RequestNavigate({
    param($s, $e)
    try { Start-Process $e.Uri.AbsoluteUri } catch {}
    $e.Handled = $true
})
# Affiche la version actuelle dans le footer
try { $ctrl.VersionRun.Text = " · v$($script:AppVersion)" } catch {}

# Vérification MAJ via API GitHub Releases
$ctrl.BtnCheckUpdate.Add_Click({
    try {
        $url = "https://api.github.com/repos/$($script:GitHubRepo)/releases/latest"
        $headers = @{ 'User-Agent' = "TitaliumRepair/$($script:AppVersion)"; 'Accept' = 'application/vnd.github+json' }
        $resp = Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 10 -EA Stop
        $latest = ($resp.tag_name -replace '^v','').Trim()
        $current = $script:AppVersion
        $isNewer = $false
        try {
            $a = [version]$latest
            $b = [version]$current
            $isNewer = $a -gt $b
        } catch { $isNewer = ($latest -ne $current) }
        if ($isNewer) {
            $msg = "Une nouvelle version est disponible !`r`n`r`nVersion installée : v$current`r`nVersion publiée  : v$latest`r`n`r`nNotes :`r`n$($resp.body)`r`n`r`nOuvrir la page de téléchargement ?"
            $r = [System.Windows.MessageBox]::Show($msg, 'Titalium - Mise à jour disponible', 'YesNo', 'Information')
            if ($r -eq 'Yes') { Start-Process $resp.html_url }
        } else {
            Show-Info "Tu es à jour : v$current (dernière publiée : v$latest)." 'Titalium'
        }
    } catch {
        Show-Warning "Impossible de joindre GitHub :`r`n$($_.Exception.Message)`r`n`r`nVérifie ta connexion ou édite `$script:GitHubRepo dans le script."
    }
})

# Header — Logs
$ctrl.BtnExportLogs.Add_Click({
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = 'TXT|*.txt|Tous|*.*'
    $sfd.FileName = "TitaliumLog-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    if ($sfd.ShowDialog() -eq 'OK') {
        try {
            $sync.Log.Text | Out-File -FilePath $sfd.FileName -Encoding UTF8 -Force
            Show-Info "Logs exportés vers :`n$($sfd.FileName)"
        } catch { Show-Warning "Erreur : $($_.Exception.Message)" }
    }
})
$ctrl.BtnClearLogs.Add_Click({
    $sync.Log.Clear()
})

# Annuler
$ctrl.BtnCancel.Add_Click({
    $sync.CancelRequested = $true
    Write-Log "[ANNULATION] Demande d'arrêt envoyée." 'WARN'
    try {
        if ($sync.CurrentPS) { $sync.CurrentPS.Stop() }
    } catch {}
})

# --- Bindings v2 (nouvelles fonctionnalités) ---

# Tableau de bord
$ctrl.BtnDashRefresh.Add_Click({ Refresh-Dashboard })

# WiFi
$ctrl.BtnWifiPasswords.Add_Click({ Invoke-Async (Op-WifiPasswords) 'Lecture WiFi...' })
$ctrl.BtnWifiExport.Add_Click({
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = 'CSV|*.csv'
    $sfd.FileName = "wifi-profiles-$(Get-Date -Format 'yyyyMMdd').csv"
    if ($sfd.ShowDialog() -eq 'OK') { Invoke-Async (Op-WifiExport -File $sfd.FileName) 'Export WiFi...' }
})

# Caches navigateurs
$ctrl.BtnCleanBrowsers.Add_Click({
    if (Confirm-Action "Vider les caches d'Edge, Chrome, Firefox et Brave ?`nLes navigateurs en cours seront fermés.") {
        Invoke-Async (Op-CleanBrowsers) 'Caches navigateurs...'
    }
})

# Hibernation
$ctrl.BtnHibernateOff.Add_Click({
    if (Confirm-Action "Désactiver l'hibernation et supprimer hiberfil.sys ?`nGain : ~RAM Go sur le disque système.") {
        Invoke-Async (Op-HibernateOff) 'Désactivation hibernation...'
    }
})
$ctrl.BtnHibernateOn.Add_Click({ Invoke-Async (Op-HibernateOn) 'Activation hibernation...' })
$ctrl.BtnHibernateStatus.Add_Click({ Invoke-Async (Op-HibernateStatus) 'Statut hibernation...' })

# File d'impression
$ctrl.BtnPrintQueue.Add_Click({
    if (Confirm-Action "Vider la file d'impression bloquée ?`nLe service Spooler sera redémarré.") {
        Invoke-Async (Op-PrintQueueClear) 'File impression...'
    }
})

# Télémétrie
$ctrl.BtnTelemetryStatus.Add_Click({ Invoke-Async (Op-TelemetryStatus) 'Statut télémétrie...' })
$ctrl.BtnTelemetryOff.Add_Click({
    if (Confirm-Action "Désactiver la télémétrie Windows (DiagTrack, dmwappushservice, WerSvc) ?`nUn backup de l'état actuel sera créé automatiquement.") {
        Invoke-Async (Op-TelemetryOff) 'Désactivation télémétrie...'
    }
})
$ctrl.BtnTelemetryOn.Add_Click({
    if (Confirm-Action "Réactiver la télémétrie Windows aux réglages standards ?") {
        Invoke-Async (Op-TelemetryOn) 'Réactivation télémétrie...'
    }
})

# BSOD
$ctrl.BtnBsodList.Add_Click({ Invoke-Async (Op-BsodList) 'Lecture BSOD...' })
$ctrl.BtnBsodMinidump.Add_Click({ Invoke-Async (Op-BsodMinidumpFolder) 'Ouverture dossier...' })

# Mode performances visuelles
$ctrl.BtnVisualPerf.Add_Click({
    if (Confirm-Action "Activer le mode « Performances maximum » ?`nDésactive animations, transparence, ombres. Reconnexion conseillée.") {
        Invoke-Async (Op-VisualPerf) 'Mode performances...'
    }
})
$ctrl.BtnVisualBest.Add_Click({
    if (Confirm-Action "Restaurer les effets visuels par défaut de Windows ?") {
        Invoke-Async (Op-VisualBest) 'Restauration effets...'
    }
})

# Bloatware
$ctrl.BtnBloatList.Add_Click({ Invoke-Async (Op-BloatList) 'Recherche bloatware...' })
$ctrl.BtnBloatRemove.Add_Click({
    $sel = @($sync.BloatList | Where-Object { $_.Selected })
    if ($sel.Count -eq 0) { Show-Warning "Coche au moins un package à désinstaller."; return }
    if (Confirm-Action "Désinstaller les $($sel.Count) package(s) sélectionné(s) ?`nCertains sont difficilement réinstallables sans réinitialisation Windows.") {
        Invoke-Async (Op-BloatRemove) 'Désinstallation...'
    }
})

# Profils
$ctrl.BtnProfileWeekly.Add_Click({
    if (Confirm-Action "Lancer le profil « Nettoyage hebdo » ?") { Invoke-Async (Op-ProfileWeekly) 'Nettoyage hebdo...' }
})
$ctrl.BtnProfileRepair.Add_Click({
    if (Confirm-Action "Lancer le profil « Réparation système complète » ? (durée : 30+ min)") { Invoke-Async (Op-ProfileRepair) 'Réparation profil...' }
})
$ctrl.BtnProfilePresale.Add_Click({
    if (Confirm-Action "Lancer le profil « Avant vente PC » ?`nDésinstalle bloatware + nettoie caches + crée point de restauration." 'Action préparatoire à la revente') {
        Invoke-Async (Op-ProfilePresale) 'Avant vente...'
    }
})
$ctrl.BtnProfileFolder.Add_Click({ Start-Process explorer.exe $sync.ProfilesDir })
$ctrl.BtnProfileNew.Add_Click({
    $name = Prompt-Text "Nom du nouveau profil :" "Nouveau profil"
    if (-not $name) { return }
    $file = Join-Path $sync.ProfilesDir "$name.json"
    if (Test-Path $file) { Show-Warning "Un profil portant ce nom existe déjà."; return }
    $template = @{
        Name = $name
        Created = (Get-Date).ToString('s')
        Operations = @('Op-CleanUserTemp','Op-NetFlushDns')
        Description = "Modifie ce fichier JSON pour personnaliser les opérations à enchaîner."
    }
    $template | ConvertTo-Json -Depth 5 | Set-Content -Path $file -Encoding UTF8
    Refresh-Profiles
    Show-Info "Profil créé : $file`nÉdite ce fichier puis utilise « Charger » + « Exécuter »."
})
$ctrl.BtnProfileDelete.Add_Click({
    $sel = $ctrl.ProfilesList.SelectedItem
    if (-not $sel) { Show-Warning "Sélectionne un profil."; return }
    $file = Join-Path $sync.ProfilesDir "$sel.json"
    if (Confirm-Action "Supprimer le profil « $sel » ?") {
        Remove-Item -Path $file -Force -EA SilentlyContinue
        Refresh-Profiles
    }
})
$ctrl.BtnProfileLoad.Add_Click({
    $sel = $ctrl.ProfilesList.SelectedItem
    if (-not $sel) { Show-Warning "Sélectionne un profil."; return }
    $file = Join-Path $sync.ProfilesDir "$sel.json"
    Start-Process notepad.exe $file
})
$ctrl.BtnProfileRun.Add_Click({
    $sel = $ctrl.ProfilesList.SelectedItem
    if (-not $sel) { Show-Warning "Sélectionne un profil."; return }
    $file = Join-Path $sync.ProfilesDir "$sel.json"
    if (-not (Test-Path $file)) { Show-Warning "Fichier introuvable."; return }
    try {
        $cfg = Get-Content -Path $file -Raw -Encoding UTF8 | ConvertFrom-Json
        $ops = @($cfg.Operations)
        if ($ops.Count -eq 0) { Show-Warning "Aucune opération définie dans le profil."; return }
        if (-not (Confirm-Action "Exécuter le profil « $sel » ($($ops.Count) opération(s)) ?")) { return }
        $sync.ProfileOps = $ops
        Invoke-Async (Wrap-Action {
            Write-LogTitle "Exécution profil"
            foreach ($opName in $sync.ProfileOps) {
                if ($sync.CancelRequested) { Write-Log "Annulé." 'WARN'; return }
                Write-Log "→ $opName"
                $cmd = Get-Command $opName -EA SilentlyContinue
                if (-not $cmd) { Write-Log "  ✗ Fonction inconnue : $opName" 'WARN'; continue }
                try { & $opName | Out-Null; Write-Log "  ✓ $opName terminé" } catch { Write-Log "  ✗ $opName : $($_.Exception.Message)" 'WARN' }
            }
            Write-Log "Profil terminé." 'OK'
        }) "Profil $sel..."
    } catch { Show-Warning "Erreur de lecture : $($_.Exception.Message)" }
})

# God Mode + shells
$ctrl.BtnGodMode.Add_Click({ Invoke-Async (Op-GodMode) 'Création God Mode...' })
$ctrl.BtnElevatedShell.Add_Click({ Start-Process 'powershell.exe' -Verb RunAs })
$ctrl.BtnElevatedCmd.Add_Click({ Start-Process 'cmd.exe' -Verb RunAs })

# Sidebar — switch panel
$panelMap = @{
    'Dashboard'   = $ctrl.PanelDashboard
    'Repair'      = $ctrl.PanelRepair
    'Update'      = $ctrl.PanelUpdate
    'Clean'       = $ctrl.PanelClean
    'Registry'    = $ctrl.PanelRegistry
    'Network'     = $ctrl.PanelNetwork
    'Winget'      = $ctrl.PanelWinget
    'Drivers'     = $ctrl.PanelDrivers
    'Performance' = $ctrl.PanelPerformance
    'Security'    = $ctrl.PanelSecurity
    'Recovery'    = $ctrl.PanelRecovery
    'Info'        = $ctrl.PanelInfo
    'Tools'       = $ctrl.PanelTools
    'Advanced'    = $ctrl.PanelAdvanced
}
$ctrl.CategoryList.Add_SelectionChanged({
    $sel = $ctrl.CategoryList.SelectedItem
    if (-not $sel) { return }
    $tag = $sel.Tag
    foreach ($k in $panelMap.Keys) {
        $panelMap[$k].Visibility = if ($k -eq $tag) { 'Visible' } else { 'Collapsed' }
    }
    if ($tag -eq 'Dashboard') { Refresh-Dashboard }
    if ($tag -eq 'Advanced')  { Refresh-Profiles }
})

#endregion

#region Démarrage
$window.Add_Loaded({
    try {
        Init-Particles
        Write-LogTitle "Titalium Repair Tool v1.0"
        Write-Log "Session démarrée par $env:USERNAME sur $env:COMPUTERNAME."
        Write-Log "Backups  : $($sync.BackupDir)"
        Write-Log "Logs     : $($sync.LogDir)"
        Write-Log "Profils  : $($sync.ProfilesDir)"
        Write-Log "Prêt. Sélectionne une catégorie à gauche."
        Refresh-Dashboard
        Refresh-Profiles
    } catch {
        try { Write-Log "Loaded handler : $($_.Exception.Message)" 'ERROR' } catch {}
        [System.Windows.MessageBox]::Show("Erreur au chargement :`r`n$($_.Exception.Message)", "Titalium", "OK", "Warning") | Out-Null
    }
})

$window.Add_Closing({
    if ($sync.Busy) {
        if (-not (Confirm-Action "Une opération est en cours. Vraiment quitter ?")) {
            $_.Cancel = $true
            return
        }
        try { if ($sync.CurrentPS) { $sync.CurrentPS.Stop() } } catch {}
    }
})

$window.Add_Closed({
    try { if ($sync.RenderTimer) { $sync.RenderTimer.Stop() } } catch {}
    try { if ($sync.UITimer) { $sync.UITimer.Stop() } } catch {}
    try {
        if ($sync.Runspace) { $sync.Runspace.Close(); $sync.Runspace.Dispose() }
    } catch {}
})

[void]$window.ShowDialog()
#endregion
