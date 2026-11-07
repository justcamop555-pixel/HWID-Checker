using HwidDesktop;
using System.Text.Json;

try
{
    switch (args[0])
    {
        case "read":
            Console.WriteLine(JsonSerializer.Serialize(SharedSnapshotLibrary.Read(args[1])));
            break;
        case "catalog":
            Console.WriteLine(JsonSerializer.Serialize(await SnapshotStore.ReadAsync(args.Skip(1))));
            break;
        case "export":
            using (var client = new EngineClient(args[1]))
            using (var snapshot = JsonDocument.Parse(File.ReadAllText(args[2])))
                Console.WriteLine((await client.ExportAsync(snapshot.RootElement, args[3], CancellationToken.None)).GetRawText());
            break;
        default:
            Console.WriteLine(JsonSerializer.Serialize(await SharedSnapshotLibrary.UpdateAsync(args[0], args.ElementAtOrDefault(2), args[1])));
            break;
    }
}
catch (Exception error)
{
    Console.WriteLine(JsonSerializer.Serialize(new { Failed = true, error.Message }));
}
