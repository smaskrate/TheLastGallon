import java.io.File;
import java.io.PrintStream;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Stream;

/**
 * Runs a Lua script on the Kahlua VM shipped inside projectzomboid.jar.
 *
 * The game's classes are compiled for Java 25 (class version 69) while the
 * tooling JDK is 17, so this file only touches Kahlua through reflection and
 * must be launched with the game's own jre64\bin\java.exe and the game jar on
 * the classpath. The working directory must be the game install directory,
 * because J2SEPlatform.setupEnvironment() loads ./stdlib.lua exactly like the
 * game does.
 *
 * Usage: KahluaRunner --root <dir> [--root <dir> ...] <entry.lua> [args...]
 *
 * Every *.lua file below each root is exposed to Lua as __TLG_SOURCES["a/b/c"]
 * (path relative to the root, forward slashes, no extension) so that the
 * prelude can implement PZ-style require "a/b/c". The process exit code is the
 * numeric value of the global __TLG_EXIT_CODE (default 0) or 2 when the entry
 * script raised an error.
 */
public final class KahluaRunner {
    private KahluaRunner() {
    }

    public static void main(String[] args) throws Exception {
        List<Path> roots = new ArrayList<>();
        String entry = null;
        List<String> scriptArgs = new ArrayList<>();
        for (int i = 0; i < args.length; i++) {
            if (entry == null && args[i].equals("--root") && i + 1 < args.length) {
                roots.add(Paths.get(args[++i]).toAbsolutePath().normalize());
            } else if (entry == null) {
                entry = args[i];
            } else {
                scriptArgs.add(args[i]);
            }
        }
        if (entry == null) {
            System.err.println("usage: KahluaRunner --root <dir> ... <entry.lua> [args]");
            System.exit(64);
        }
        if (!new File("stdlib.lua").isFile()) {
            System.err.println("stdlib.lua not found in working directory; run from the game install dir");
            System.exit(65);
        }

        Class<?> platformClass = Class.forName("se.krka.kahlua.j2se.J2SEPlatform");
        Class<?> platformIface = Class.forName("se.krka.kahlua.vm.Platform");
        Class<?> tableIface = Class.forName("se.krka.kahlua.vm.KahluaTable");
        Class<?> threadClass = Class.forName("se.krka.kahlua.vm.KahluaThread");
        Class<?> compilerClass = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler");

        Object platform = platformClass.getMethod("getInstance").invoke(null);
        Object env = platformClass.getMethod("newEnvironment").invoke(platform);
        Method newTable = platformClass.getMethod("newTable");
        Method rawset = tableIface.getMethod("rawset", Object.class, Object.class);
        Method rawget = tableIface.getMethod("rawget", Object.class);

        Object sources = newTable.invoke(platform);
        for (Path root : roots) {
            if (!Files.isDirectory(root)) {
                System.err.println("root is not a directory: " + root);
                System.exit(66);
            }
            try (Stream<Path> walk = Files.walk(root)) {
                for (Path p : (Iterable<Path>) walk.filter(f -> f.toString().endsWith(".lua"))::iterator) {
                    String rel = root.relativize(p).toString().replace('\\', '/');
                    String key = rel.substring(0, rel.length() - 4);
                    if (rawget.invoke(sources, key) == null) {
                        rawset.invoke(sources, key, Files.readString(p, StandardCharsets.UTF_8));
                    }
                }
            }
        }
        rawset.invoke(env, "__TLG_SOURCES", sources);

        Object argTable = newTable.invoke(platform);
        for (int i = 0; i < scriptArgs.size(); i++) {
            rawset.invoke(argTable, Double.valueOf(i + 1), scriptArgs.get(i));
        }
        rawset.invoke(env, "__TLG_ARGS", argTable);

        Object thread = threadClass.getConstructor(PrintStream.class, platformIface, tableIface)
                .newInstance(System.out, platform, env);
        // The PZ fork of KahluaThread.pcall dereferences debugOwnerThread.
        threadClass.getField("debugOwnerThread").set(thread, Thread.currentThread());
        Method loadstring = compilerClass.getMethod("loadstring", String.class, String.class, tableIface);
        Method pcall = threadClass.getMethod("pcall", Object.class, Object[].class);

        Path entryPath = Paths.get(entry).toAbsolutePath().normalize();
        String source = Files.readString(entryPath, StandardCharsets.UTF_8);
        Object closure;
        try {
            closure = loadstring.invoke(null, source, entryPath.getFileName().toString(), env);
        } catch (java.lang.reflect.InvocationTargetException e) {
            System.out.println("COMPILE ERROR: " + e.getCause());
            System.exit(3);
            return;
        }
        Object[] result = (Object[]) pcall.invoke(thread, closure, new Object[0]);
        System.out.flush();
        if (result.length == 0 || !Boolean.TRUE.equals(result[0])) {
            System.out.println("LUA ERROR: " + (result.length > 1 ? result[1] : "<no message>"));
            if (result.length > 2 && result[2] != null) {
                System.out.println(result[2]);
            }
            System.exit(2);
        }
        Object code = rawget.invoke(env, "__TLG_EXIT_CODE");
        System.exit(code instanceof Double ? ((Double) code).intValue() : 0);
    }
}
