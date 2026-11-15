namespace Vemas.MailRelay.Domain;

/// <summary>Zum Versand reservierte Mail aus der Queue.</summary>
public sealed class QueuedMessage
{
    public long MessageId { get; set; }
    public int ProfileId { get; set; }
    public string EnvelopeTo { get; set; } = string.Empty;
    public byte[] Mime { get; set; }
    public int AttemptCount { get; set; }

    public IReadOnlyList<string> GetEnvelopeRecipients()
    {
        return EnvelopeTo.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    }
}
