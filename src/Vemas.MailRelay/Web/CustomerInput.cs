using System.ComponentModel.DataAnnotations;
using Vemas.MailRelay.Domain;

namespace Vemas.MailRelay.Web;

/// <summary>Formularmodell für Anlegen/Bearbeiten eines Kunden.</summary>
public sealed class CustomerInput
{
    public int CustomerId { get; set; }

    [Required(ErrorMessage = "Name ist erforderlich.")]
    [StringLength(200)]
    public string Name { get; set; }

    [Required(ErrorMessage = "Kurzname ist erforderlich.")]
    [StringLength(50)]
    [RegularExpression(@"^[A-Za-z0-9_.-]+$", ErrorMessage = "Kurzname: nur Buchstaben, Ziffern, Punkt, Bindestrich, Unterstrich.")]
    public string ShortName { get; set; }

    /// <summary>Ein Windows-Login bzw. eine Windows-Gruppe pro Zeile, z.B. DOMAENE\svc-nextgen-kunde.</summary>
    public string Logins { get; set; }

    public bool IsActive { get; set; } = true;

    public static CustomerInput FromCustomer(Customer customer)
    {
        return new CustomerInput
        {
            CustomerId = customer.CustomerId,
            Name = customer.Name,
            ShortName = customer.ShortName,
            Logins = string.Join(Environment.NewLine, customer.Logins),
            IsActive = customer.IsActive
        };
    }

    public Customer ToCustomer()
    {
        return new Customer
        {
            CustomerId = CustomerId,
            Name = Name,
            ShortName = ShortName,
            IsActive = IsActive,
            Logins = GetLoginList()
        };
    }

    public List<string> GetLoginList()
    {
        return (Logins ?? string.Empty)
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }
}
