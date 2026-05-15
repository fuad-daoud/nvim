local java_debug_jar = '/usr/share/java-debug/com.microsoft.java.debug.plugin.jar'

return {
  {
    'JavaHello/spring-boot.nvim',
    ft = { 'java', 'yaml', 'jproperties' },
    dependencies = { 'mfussenegger/nvim-jdtls' },
    init = function()
      -- Directory containing the 4 Eclipse plugin JARs from the STS4 build / VSIX extraction:
      --   jdt-ls-commons.jar, jdt-ls-extension.jar,
      --   io.projectreactor.reactor-core.jar, org.reactivestreams.reactive-streams.jar
      vim.g.spring_boot = {
        jdt_extensions_path = vim.fn.expand '~/.local/share/spring-boot-ls/jars',
      }
    end,
    opts = {
      ls_path = vim.fn.expand '~/.local/share/spring-boot-ls/spring-boot-language-server.jar',
      jdtls_name = 'jdtls',
    },
  },

  {
    'mfussenegger/nvim-jdtls',
    ft = 'java',
    config = function()
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'java',
        callback = function()
          local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ':p:h:t')
          local workspace_dir = vim.fn.expand '~/.local/share/eclipse/' .. project_name

          local bundles = {}
          if vim.fn.filereadable(java_debug_jar) == 1 then
            table.insert(bundles, java_debug_jar)
          end
          -- java_extensions() applies a name filter that expects VSIX artifact-ID names
          -- (io.projectreactor.reactor-core.jar) but our jars have versioned BOOT-INF names
          -- (reactor-core-3.x.jar), causing it to silently drop 2 of the 4 required JARs.
          -- Also, when called without an explicit path it falls back to Mason/VSCode lookup
          -- and returns empty. Glob directly to load all 4 JARs reliably.
          local spring_jars_dir = vim.fn.expand '~/.local/share/spring-boot-ls/jars'
          vim.list_extend(
            bundles,
            vim.tbl_filter(function(f)
              return f ~= ''
            end, vim.split(vim.fn.glob(spring_jars_dir .. '/*.jar'), '\n'))
          )

          require('jdtls').start_or_attach {
            cmd = { 'jdtls', '-data', workspace_dir },
            root_dir = vim.fs.root(0, { '.git', 'pom.xml', 'build.gradle', 'build.gradle.kts', 'settings.gradle', 'settings.gradle.kts' }),
            capabilities = require('blink.cmp').get_lsp_capabilities(),
            init_options = {
              bundles = bundles,
            },
            on_attach = function(_, bufnr)
              require('spring_boot').init_lsp_commands()

              if vim.fn.filereadable(java_debug_jar) == 1 then
                require('jdtls').setup_dap { hotcodereplace = 'auto' }
                require('jdtls.dap').setup_dap_main_class_configs()
              end

              local map = function(keys, func, desc)
                vim.keymap.set('n', keys, func, { buffer = bufnr, desc = 'Java: ' .. desc })
              end
              map('<leader>sjo', require('jdtls').organize_imports, '[O]rganize imports')
              map('<leader>sjv', require('jdtls').extract_variable, 'Extract [V]ariable')
              map('<leader>sjm', require('jdtls').extract_method, 'Extract [M]ethod')
              map('<leader>sjc', require('jdtls').extract_constant, 'Extract [C]onstant')
              map('<leader>sjd', require('jdtls.dap').pick_test, 'Debug [T]est')

              -- Static Spring pickers via ripgrep — no spring-boot-ls server dependency.
              -- spring-boot-ls workspace/symbol queries require the jdtls↔spring-boot-ls classpath
              -- bridge to fully initialise before returning data; rg is instant and reliable.
              local function rg_spring_pick(pattern, title)
                local root = vim.fs.root(0, { '.git', 'pom.xml', 'build.gradle', 'build.gradle.kts' })
                if not root then
                  vim.notify('No project root found', vim.log.levels.WARN)
                  return
                end
                local src = vim.fn.isdirectory(root .. '/src/main/java') == 1 and root .. '/src/main/java' or root
                local out = {}
                vim.fn.jobstart({ 'rg', '--json', '--type', 'java', pattern, src }, {
                  stdout_buffered = true,
                  on_stdout = function(_, data)
                    vim.list_extend(out, data)
                  end,
                  on_exit = function()
                    local items = {}
                    for _, line in ipairs(out) do
                      if line ~= '' then
                        local ok, obj = pcall(vim.json.decode, line)
                        if ok and obj.type == 'match' then
                          table.insert(items, {
                            text = vim.trim(obj.data.lines.text),
                            file = obj.data.path.text,
                            pos = { obj.data.line_number, 0 },
                          })
                        end
                      end
                    end
                    vim.schedule(function()
                      if #items == 0 then
                        vim.notify('No Spring ' .. title .. ' found', vim.log.levels.WARN)
                        return
                      end
                      Snacks.picker.pick { items = items, title = 'Spring ' .. title }
                    end)
                  end,
                })
              end

              map('<leader>sjb', function()
                rg_spring_pick('@(Component|Service|Repository|Controller|RestController|Configuration|Bean)', 'Beans')
              end, 'Spring [B]eans')
              map('<leader>sje', function()
                rg_spring_pick('@(Get|Post|Put|Delete|Patch|Request)Mapping', 'Endpoints')
              end, 'Spring [E]ndpoints')
              -- Dedicated spring-boot hover: vim.lsp.buf.hover() shows jdtls Javadoc first,
              -- discarding spring-boot-ls bean-candidate info. Query spring-boot client directly.
              map('<leader>sjh', function()
                local sb_client = require('spring_boot.util').get_spring_boot_client()
                if not sb_client then
                  vim.notify('Spring Boot LS not attached', vim.log.levels.WARN)
                  return
                end
                local params = vim.lsp.util.make_position_params(0, sb_client.offset_encoding)
                sb_client:request('textDocument/hover', params, function(err, result)
                  if err then
                    vim.notify('Spring Boot hover: ' .. vim.inspect(err), vim.log.levels.ERROR)
                    return
                  end
                  local lines = result and result.contents and vim.lsp.util.convert_input_to_markdown_lines(result.contents) or {}
                  lines = vim.lsp.util.trim_empty_lines(lines)
                  if vim.tbl_isempty(lines) then
                    vim.notify('Spring Boot: no bean info (cursor not on a Spring-managed type, or classpath bridge not ready)', vim.log.levels.INFO)
                    return
                  end
                  vim.lsp.util.open_floating_preview(lines, 'markdown', { border = 'rounded', focusable = true })
                end, 0)
              end, 'Spring Boot [H]over')
            end,
          }
        end,
      })
    end,
  },
}
