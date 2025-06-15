namespace :erd_xml_parser do
  desc "Parse draw.io xml file with FK, PK, enum rules"
  task parse: :environment do
    require "nokogiri"

    file_path = "erd.drawio.xml"  # 你把xml路徑填這
    xml = File.read(file_path)
    doc = Nokogiri::XML(xml)

    tables = {}

    # 先建立一個 helper 判斷這個欄位是否有子元素
    # 子元素通常是對應到 <mxCell parent="該欄位id" ...>
    # 所以先建立 id -> 子元素數量 map
    parent_counts = Hash.new(0)
    doc.xpath("//mxCell[@parent]").each do |cell|
      parent_id = cell["parent"]
      parent_counts[parent_id] += 1
    end
    setting_modules = []
    setting_module_parent_id = nil
    doc.xpath("//mxCell[contains(@style, 'swimlane')]").each do |table_cell|
      table_name = table_cell["value"]
      next if table_name.blank?
      unless table_name =~ /\A[a-zA-Z0-9_]+\z/\

        if table_name == "基本設定"
          setting_module_parent_id = table_cell["id"]
        end
        next
      end

      table_id = table_cell["id"]
      tables[table_name] = []
      if table_cell["parent"] == setting_module_parent_id
        setting_modules << table_name
      end
      # 找出此table底下所有欄位（mxCell的parent是table_id）
      doc.xpath("//mxCell[@parent='#{table_id}']").each do |field_cell|
        value = field_cell["value"]
        style = field_cell["style"]
        next if value.blank?
        
        column_id = field_cell["id"]
        has_children = parent_counts[column_id] > 0

        # 是否是 PK 或 FK (以子元素的style判斷)
        # 這邊用子元素 style 判斷 PK 或 FK，假設子元素 style 裡有 'PK' 或 'FK' 關鍵字
        child_cells = doc.xpath("//mxCell[@parent='#{column_id}']")
        is_pk = child_cells.any? { |c| c["value"]&.include?("PK") }
        is_fk = child_cells.any? { |c| c["value"]&.include?("FK") }
        add_index = style&.include?("fontStyle=4")

        column_name = value.split(": ").first
        raw_type = value.split(": ").second&.split&.first
        comment = value.split(": ").second&.split&.second
          if raw_type&.include?("decimal")
                    precision, scale = raw_type.scan(/\d+/).map(&:to_i)
                    raw_type =  "decimal"
                      
          end
        raw_type = if raw_type == "text(JSON)"
                     "text"
                      else
                        raw_type
                    end
        column_name = if column_name == "password"
          "password_digest"
        else
          column_name
        end
        
        # 主鍵不用額外設定欄位，跳過
        if is_pk
          # 可以記錄一下主鍵資訊，但這裡跳過欄位加入
          next
        end

        column_type =
          if is_fk && has_children
            "references" # FK 的話用 reference
          else
            case raw_type
            when "int", "integer", "bigint"
              "integer"
            when "string", "varchar", "char"
              "string"
            when "text"
              "text"
            when "boolean", "bool"
              "boolean"
            when "datetime", "timestamp"
              "datetime"
            when "date"
              "date"
            when "decimal", "numeric"
              "decimal"
            when "float", "double"
              "float"
            when "enum"
              "integer" # enum 改為 integer，預設 0
            else
              "string"
            end
          end

        # 加入欄位資訊，enum 型別時加上預設值 0
        column_hash = { name: column_name, type: column_type, comment: }
        if raw_type == "enum"
          column_hash[:default] = 0
        end
        if raw_type == "decimal"
          column_hash[:precision] = precision
          column_hash[:scale] = scale
        end
         if add_index
            column_hash[:underlined] = true
          end
          if is_fk
            column_hash[:fk] = true
          end

        tables[table_name] << column_hash
      end
    end

    # 印出結果
    tables.each do |table_name, fields|
      g =  "rails g model #{table_name} --no-test-framework --force"

      system(g)
    end

    tables.each do |table_name, fields|
      model_name = table_name.singularize.camelize
      model_file = "app/models/#{model_name.underscore}.rb"

      content = <<~RUBY
        class #{model_name} < ApplicationRecord
      RUBY

      fields.each do |field|
        if field[:type] == 'references' || field[:fk]
          ref_name = field[:name].sub(/_id$/, '')
          content += "  belongs_to :#{ref_name}\n"
        end
      end

      content += "end\n"

      File.write(model_file, content)
      puts "已重寫 model 檔案: #{model_file}"
    end

    

    # 建立migration欄位
    tables.each do |table_name, fields|
      migration_pattern = "db/migrate/*_create_#{table_name.underscore.pluralize}.rb"
      migration_file = Dir.glob(migration_pattern).max_by { |f| File.mtime(f) }
      
      if migration_file.nil?
        puts "找不到 #{table_name} 的 migration 檔案！"
        next
      end

      # Rails migration 檔案標準版頭 (可以依你Rails版本調整)
      migration_version = "[7.1]"  # 或自己改成你的rails版本
      migration_class_name = "Create#{table_name.camelize.pluralize}"

      # 欄位字串
      columns_str = fields.map do |field|
        default_str = field[:default] ? ", default: #{field[:default]}" : ""
        precision_str = field[:precision] ? ", precision: #{field[:precision]}" : ""
        scale_str = field[:scale] ? ", scale: #{field[:scale]}" : ""
        "        t.#{field[:type]} :#{field[:name]}#{precision_str}#{scale_str}#{default_str}"
      end.join("\n")

      # index 字串放在 timestamps 之後
      indexes_str = fields.select { |f| f[:underlined] }.map do |field|
        "        t.index :#{field[:name]}, unique: true"
      end.join("\n")

      # 組成完整檔案內容
      new_content = <<~RUBY
        class #{migration_class_name} < ActiveRecord::Migration#{migration_version}
          def change
            create_table :#{table_name} do |t|
      #{columns_str}

              t.timestamps

      #{indexes_str}
            end
          end
        end
      RUBY

      File.write(migration_file, new_content)

      puts "已重寫整個 #{migration_file}"
    end


    route_path = "config/routes.rb"

    setting_content = setting_modules.map do |m|
      "    resources :#{m}"
    end.join("\n")

  content = <<~RUBY
    Rails.application.routes.draw do
      # 基本設定模組
      get "setting", to: "session#setting_index", as: "setting_root"
      post "reset_password", to: "setting/users#reset_password"
      namespace :setting do
    #{setting_content}
      end
    end
  RUBY

  File.write(route_path, content)
  puts "已重寫 routes.rb 完成"

  setting_modules.each do |m|
    g =  "rails g controller setting/#{m} --no-test-framework --force"

    system(g)
  end

  setting_modules.each do |m|
    module_name = m.singularize
    controller_name = "#{m}_controller"
    controller_file = "app/controllers/setting/#{controller_name}.rb"
    class_name = m.singularize.camelize
    controller_class_name = "Setting::#{m.singularize.camelize}"



    search_str =  tables["#{m}"].map do |field|
    pp field
      if field[:fk] == true
      "      #{field[:name]}_id: params[:#{field[:name]}_id],"
      else
      "      #{field[:name]}: params[:#{field[:name]}],"
      end
    end.join("\n")

    fk_column = tables["#{m}"].select do |field|
      field[:fk] == true
    end

    if fk_column.present?
      relative_before_action_str = "before_action -> { related_attributes }\n"
      relative_attribute_str = fk_column.map do |field|
        "      @#{field[:name].pluralize} = #{field[:name].singularize.camelize}::List.result.enabled_#{field[:name].pluralize}"
      end.join("\n")
      relative_function_str = <<~RUBY
      def related_attributes
      #{relative_attribute_str}
      end
      RUBY
    else
      relative_before_action_str = ""
      relative_function_str = ""
    end

    relative_function_str = 

    content = <<~RUBY
    class #{controller_class_name} < ApplicationController
      before_action -> { permission_check("#{module_name}", "search") }, only: [:index]
      before_action -> { permission_check("#{module_name}", "edit") }, only: [:new, :edit, :create, :update]
      #{relative_before_action_str}
      def index
        #{m} = #{class_name}::List.result(search_params).#{m}
        @pagy, @#{m} = pagy(#{m})
      end

      def new
        @#{m} = #{class_name}.new(state: "enable")
      end

      def edit
        @#{m} = #{class_name}::Find.result(#{m}_params).#{m}
      end

      def create
        actor = #{class_name}::Create.result(#{m}_params)
        render_json(actor)
      end

      def update
        actor = #{class_name}::Update.result(#{m}_params)
        render_json(actor)
      end

      private
      #{relative_function_str}
      def #{m}_params
        {
          #{m}_id: params[:id],
          params:,
        }
      end
      
      def search_params
        {
    #{search_str}
        }
      end
    end
    RUBY


      File.write(controller_file, content)
      puts "已重寫 controller 檔案: #{controller_file}"
  end


  end
end
