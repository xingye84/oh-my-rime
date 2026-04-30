-- 五笔拼音混输拼音学习：
-- 仅记录当前输入中出现过的拼音候选；真正上屏后再写入 rime_mint 用户词典

local shared = require("wubi_mixed_shared")

local M = {}

local kNoop = 2

local function should_enable(schema_id)
    return schema_id == "wubi86_jidian_mixed" or schema_id == "wubi98_mint_mixed"
end

function M.init(env)
    if env.notifier_connected then
        return
    end

    local engine = env.engine
    env.commit_notifier = engine.context.commit_notifier:connect(function()
        if not should_enable(engine.schema.schema_id) then
            return
        end

        local candidates = shared.candidates
        if not candidates then
            return
        end

        local history = engine.context.commit_history
        if not history or history:size() == 0 then
            return
        end

        local record = history:back()
        local text = record and record.text
        if not text or text == "" then
            return
        end

        local code = candidates[text]
        if not code or code == "" then
            return
        end

        local ok_schema, pinyin_schema = pcall(Schema, "rime_mint")
        if not ok_schema or not pinyin_schema then
            return
        end

        local ok_memory, memory = pcall(Memory, engine, pinyin_schema, "translator")
        if not ok_memory or not memory or not memory.update_userdict then
            return
        end

        local entry = DictEntry()
        entry.text = text
        entry.custom_code = code
        pcall(function()
            memory:update_userdict(entry, 5, "")
        end)

        shared.candidates = nil
    end)
    env.notifier_connected = true
end

function M.fini(env)
    if env.commit_notifier and env.notifier_connected then
        env.commit_notifier:disconnect()
        env.notifier_connected = nil
    end
end

function M.func(key, env)
    return kNoop
end

return M
