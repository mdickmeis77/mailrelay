using Microsoft.AspNetCore.Authentication.Negotiate;
using Microsoft.AspNetCore.Authorization;
using Vemas.MailRelay.Configuration;
using Vemas.MailRelay.Data;
using Vemas.MailRelay.Maintenance;
using Vemas.MailRelay.Options;
using Vemas.MailRelay.Security;
using Vemas.MailRelay.Sending;
using Vemas.MailRelay.Smtp;

const string ServiceName = "Vemas.MailRelay";

// Als Windows-Dienst ist das Arbeitsverzeichnis System32 - daher ContentRoot = EXE-Verzeichnis.
var builder = WebApplication.CreateBuilder(new WebApplicationOptions
{
    Args = args,
    ContentRootPath = AppContext.BaseDirectory
});

builder.Host.UseWindowsService(options => options.ServiceName = ServiceName);

// Optionen
builder.Services.Configure<SmtpOptions>(builder.Configuration.GetSection(SmtpOptions.SectionName));
builder.Services.Configure<WebOptions>(builder.Configuration.GetSection(WebOptions.SectionName));
builder.Services.Configure<SendingOptions>(builder.Configuration.GetSection(SendingOptions.SectionName));
builder.Services.Configure<MaintenanceOptions>(builder.Configuration.GetSection(MaintenanceOptions.SectionName));

// Datenzugriff und Konfiguration
builder.Services.AddSingleton<SqlConnectionFactory>();
builder.Services.AddSingleton<ProfileRepository>();
builder.Services.AddSingleton<SmtpUserRepository>();
builder.Services.AddSingleton<MessageQueueRepository>();
builder.Services.AddSingleton<MessageLogRepository>();
builder.Services.AddSingleton<MaintenanceRepository>();
builder.Services.AddSingleton<DashboardRepository>();
builder.Services.AddSingleton<CustomerRepository>();
builder.Services.AddSingleton<TestMailRequestRepository>();
builder.Services.AddSingleton<RelayConfigCache>();

// SMTP-Eingang
builder.Services.AddSingleton<RelayUserAuthenticator>();
builder.Services.AddSingleton<RelayMailboxFilter>();
builder.Services.AddSingleton<RelayMessageStore>();

// Versand
builder.Services.AddHttpClient(GraphMailClient.GraphClientName, client =>
{
    client.BaseAddress = new Uri(GraphMailClient.GraphBaseAddress);
    client.Timeout = TimeSpan.FromMinutes(5);
});
builder.Services.AddHttpClient(GraphMailClient.UploadClientName, client => client.Timeout = TimeSpan.FromMinutes(5));
builder.Services.AddHttpClient(MsalHttpClientFactoryAdapter.ClientName);
builder.Services.AddSingleton<MsalHttpClientFactoryAdapter>();
builder.Services.AddSingleton<GraphTokenProvider>();
builder.Services.AddSingleton<GraphMailClient>();
builder.Services.AddSingleton<LargeMessageSender>();
builder.Services.AddSingleton<GraphMailSender>();
builder.Services.AddSingleton<MessageProcessor>();
builder.Services.AddSingleton<QueueSignal>();
builder.Services.AddSingleton<TestMailService>();

// Hintergrunddienste
builder.Services.AddHostedService<ConfigRefreshService>();
builder.Services.AddHostedService<SmtpHostedService>();
builder.Services.AddHostedService<SendWorker>();
builder.Services.AddHostedService<MaintenanceService>();
builder.Services.AddHostedService<TestMailRequestService>();

// Weboberfläche: Kestrel, Windows-Anmeldung, Zugriff nur für die Admin-Gruppe
var webOptions = builder.Configuration.GetSection(WebOptions.SectionName).Get<WebOptions>() ?? new WebOptions();
builder.WebHost.ConfigureKestrel(kestrel =>
{
    var certificate = CertificateLoader.FindInMachineStore(webOptions.CertificateThumbprint);
    kestrel.ListenAnyIP(webOptions.Port, listen =>
    {
        if (certificate is not null)
        {
            listen.UseHttps(certificate);
        }
    });
});

builder.Services.AddAuthentication(NegotiateDefaults.AuthenticationScheme).AddNegotiate();
builder.Services.AddAuthorization(options =>
{
    options.FallbackPolicy = new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .RequireRole(webOptions.AdminGroup)
        .Build();
});
builder.Services.AddRazorPages();

var app = builder.Build();

app.UseStatusCodePages();
app.UseAuthentication();
app.UseAuthorization();
app.MapRazorPages();

app.Logger.LogInformation("{Service} {Version} startet. Weboberfläche auf Port {Port}, Admin-Gruppe '{Group}'.",
    ServiceName, typeof(Program).Assembly.GetName().Version, webOptions.Port, webOptions.AdminGroup);

await app.RunAsync();
