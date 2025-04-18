import * as yaml from "https://deno.land/std@0.224.0/yaml/mod.ts"; // Use current std version

// Expect the Quarto file path as the first command-line argument
if (Deno.args.length < 1) {
    console.error("Error: Quarto file path argument missing.");
    Deno.exit(1);
}
const targetFileAbs = Deno.args[0];

try {
    // Read the whole file
    const fileContent = await Deno.readTextFile(targetFileAbs);

    // Extract YAML front matter (simple regex approach)
    const fmMatch = fileContent.match(/^---\s*([\s\S]*?)\s*---/);
    if (!fmMatch || !fmMatch[1]) {
        // No front matter found, exit cleanly (code 0) as Docker isn't requested
        Deno.exit(0);
    }
    const fmYaml = fmMatch[1];

    // Parse the YAML
    const frontMatter = yaml.parse(fmYaml) as Record<string, any>;

    // Check for docker config
    if (frontMatter && typeof frontMatter.docker === 'object' && frontMatter.docker !== null) {
        const dockerConfig = frontMatter.docker as Record<string, any>;

        // Output image if found
        if (typeof dockerConfig.image === 'string' && dockerConfig.image.length > 0) {
            console.log(`IMAGE=${dockerConfig.image}`); // Output format for Bash
        } else {
            // Docker block exists but no valid image - treat as error? Or just ignore?
            // Let's ignore for now, Bash script will handle missing image later.
        }

        // Output options if found
        if (Array.isArray(dockerConfig.options)) {
            dockerConfig.options.forEach(opt => {
                if (typeof opt === 'string') {
                    console.log(`OPTION=${opt}`); // Output format for Bash
                }
            });
        }
        Deno.exit(0); // Success (found docker block, outputted info)
    } else {
        // No docker block found, exit cleanly
        Deno.exit(0);
    }

} catch (err) {
    console.error(`Error processing file ${targetFileAbs}: ${err.message}`);
    Deno.exit(1); // Exit with error code if reading/parsing fails
}
