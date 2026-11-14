namespace HwidDesktop;

internal static class ValueExplanation
{
    internal static string Identifier(IdentifierRow row) =>
        row.Field + " · " + row.Status + "\n" + J.SectionName(row.Section) + " / " + row.Device +
        "\n\n" + (row.Value.Length == 0 ? "Windows did not supply a value." : row.Value) +
        "\n\n" + (row.Value.Length > 0 ? row.Value.Length + " characters · Copy value keeps the exact original text, including leading zeros.\n" : "") +
        (row.Status switch
        {
            "Reported" => "Supplied by Windows; this does not prove the value is unique or authentic.",
            "Default" => "This looks like a generic/default value. It is not a unique device serial number.",
            "Missing" => "Missing identifiers can be normal. Check Review for read errors before assuming the device failed.",
            _ => "Review shows what was reported and any limitations of the reading."
        });

    internal static string Review(ReviewRow row) => J.SectionName(row.Section) + " · " + row.Kind +
        "\n" + row.Message + "\n\n" + row.Detail + "\n\n" + (row.Kind switch
        {
            "Read error" => "A failed read is not proof of missing or faulty hardware. Follow the next step above, then rescan.",
            "ID review" => "Next step: compare the device's other identifiers in IDs or Hardware. Do not change firmware just to fill a missing field.",
            "Conflict" => "Next step: inspect the conflicting records in Hardware, then rescan. A conflict alone does not prove spoofing or a hardware fault.",
            "Device status" => "Next step: check this device in Windows Device Manager. Disconnected or historical entries can be expected.",
            _ => "Next step: inspect this device in Hardware and rescan if its connection changed."
        });
}
