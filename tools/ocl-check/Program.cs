// Parses every .ocl file under .octopus with Octopus's OCL parser (OctopusDeploy/Ocl), as Octopus reads the Platform
// Hub repository. For a policy, the Rego that the parser reads from its conditions and scope blocks must equal what
// scripts/policies.ps1 extracted to build/rego, which opa fmt, opa check and opa test ran on.
// Usage: dotnet run --project tools/ocl-check -p:OclSource=<checkout of OctopusDeploy/Ocl> -- <repository root>

using System;
using System.IO;
using System.Linq;
using Octopus.Ocl;

var root = Path.GetFullPath(args.Length > 0 ? args[0] : ".");
var serializer = new OclSerializer();
var failures = 0;
var files = Directory.EnumerateFiles(Path.Combine(root, ".octopus"), "*.ocl", SearchOption.AllDirectories)
    .OrderBy(path => path, StringComparer.Ordinal)
    .ToList();

foreach (var path in files)
{
    var relative = Path.GetRelativePath(root, path).Replace('\\', '/');
    try
    {
        var document = serializer.Deserialize<OclDocument>(File.ReadAllText(path));
        var detail = $"{document.Count} elements";
        if (relative.StartsWith(".octopus/policies/", StringComparison.Ordinal))
        {
            var slug = Path.GetFileNameWithoutExtension(path);
            foreach (var section in new[] { "conditions", "scope" })
            {
                var block = document.OfType<OclBlock>().Single(b => b.Name == section);
                var value = block.OfType<OclAttribute>().Single(a => a.Name == "rego").Value;
                var rego = value is OclStringLiteral literal ? literal.Value : value as string
                    ?? throw new InvalidDataException($"{section}: rego is not a string");
                var extracted = File.ReadAllText(Path.Combine(root, "build", "rego", slug, section + ".rego"));
                if (extracted != rego + "\n")
                    throw new InvalidDataException($"{section}: the Rego Octopus reads differs from build/rego/{slug}/{section}.rego");
            }
            detail += "; the conditions and scope Rego equal build/rego";
        }
        Console.WriteLine($"PASS {relative}: {detail}");
    }
    catch (Exception e)
    {
        failures++;
        Console.WriteLine($"FAIL {relative}: {e.Message}");
    }
}

if (files.Count == 0)
{
    Console.WriteLine("FAIL no .ocl file under .octopus");
    return 1;
}
return failures == 0 ? 0 : 1;
