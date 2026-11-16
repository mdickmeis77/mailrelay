namespace Vemas.MailRelay.Domain;

/// <summary>Kunde (Mandant) für den Zugriff aus NextGen.</summary>
public sealed class Customer
{
    public int CustomerId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string ShortName { get; set; } = string.Empty;
    public bool IsActive { get; set; } = true;

    /// <summary>Windows-Logins bzw. -Gruppen, über die der Kunde erkannt wird (z.B. App-Pool-Konto).</summary>
    public List<string> Logins { get; set; } = [];
}
