module Pocolog
    module Upgrade
        module DSL
            # Object providing an evaluation context for the converter DSL
            class Context < BasicObject
                attr_reader :path
                attr_reader :reference_date
                attr_reader :from_type
                attr_reader :to_type
                attr_reader :source_registry
                attr_reader :target_registry
                attr_reader :converter_registry
                attr_reader :converter

                def initialize(path, converter_registry, source_registry, target_registry)
                    @path = path
                    @converter_registry = converter_registry
                    @source_registry = source_registry
                    @target_registry = target_registry
                    @deep_cast = nil
                    @reference_date = nil
                end

                def define(date_string, from_type_name, to_type_name, &block)
                    if @reference_date
                        Kernel.raise ::ArgumentError, "one can define only one converter per file"
                    end

                    @reference_date = ::DateTime.parse(date_string).to_time
                    @from_type = source_registry.get(from_type_name)
                    @to_type = target_registry.get(to_type_name)
                    @converter = converter_registry.add(reference_date, from_type, to_type, name: path.to_s, &block)
                end

                def deep_cast(target, value, relax: true, **options)
                    if !@deep_cast_ops
                        @deep_cast_ops = ::Pocolog::Upgrade.build_deep_cast(reference_date, from_type, to_type, converter_registry, relax: relax, **options)
                    end
                    @deep_cast_ops.call(target, value)
                end

                def copy(target, value)
                    ::Typelib.copy(target, ::Typelib.from_ruby(value, target.class))
                end

                def to_ruby(value)
                    ::Typelib.to_ruby(value)
                end
            end

            # Create a template converter for given time, source and target
            # types
            def self.create(output_path, reference_time, source_type, target_type, description: "Converter created at #{Time.now}")
                file_basename = reference_time.iso8601 + source_type.name.gsub('/', ':')
                existing_paths = Pathname.enum_for(:glob, output_path + (file_basename + ".*"))
                max_id = existing_paths.map do |p|
                    e = p.extname
                    if e =~ /^\.(\d+)$/
                        Integer($1)
                    end
                end.compact.max
                id = (max_id || 0) + 1

                converter_file = file_basename + "." + id.to_s
                source_tlb     = converter_file + ".source.tlb"
                target_tlb     = converter_file + ".target.tlb"

                (output_path + converter_file).open('w') do |io|
                    io.puts "# #{description}"
                    io.puts "define \"#{reference_time.to_time}\", \"#{source_type.name}\", \"#{target_type.name}\" do |target_value, source_value|"
                    io.puts "    # This would copy everything that can be copied from the source to the target"
                    io.puts "    # deep_cast(target_value, source_value)"
                    io.puts "    target_value"
                    io.puts "end"
                end
                (output_path + source_tlb).open('w') do |io|
                    io.write source_type.to_xml
                end
                (output_path + target_tlb).open('w') do |io|
                    io.write target_type.to_xml
                end
                return (output_path + converter_file), (output_path + source_tlb), (output_path + target_tlb)
            end

            # Load a directory containing custom converters generated by
            # 'rock-log create-converter'
            def self.load_dir(load_path, converter_registry)
                converters = Array.new
                Pathname.glob(Pathname.new(load_path) + "*") do |path|
                    next if !File.file?(path)
                    source_tlb = path.sub(/$/, '.source.tlb')
                    target_tlb = path.sub(/$/, '.target.tlb')
                    if source_tlb.exist? && target_tlb.exist?
                        # Assume this *is* a converter
                        source_registry = Typelib::Registry.from_xml(source_tlb.read)
                        target_registry = Typelib::Registry.from_xml(target_tlb.read)
                        context = Context.new(path.to_s, converter_registry, source_registry, target_registry)
                        context.instance_eval(path.read, path.to_s, 1)
                        if c = context.converter
                            converters << c
                        end
                    end
                end
                converters
            end
        end
    end
end
