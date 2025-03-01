--  SPDX-License-Identifier: MIT
--
--  Copyright (c) 2019-2023 LESforMacOS authors, see AUTHORS.txt
--  for a list
--
--  Distributed under the MIT software license, see the accompanying
--  file COPYING.txt or visit https://opensource.org/license/mit/

-- Compatibility code used to upgrade LES's jumpstart routine if we're upgrading from
-- older versions. To be retained for a maximum of two releases, after which it should
-- be removed. We will not be including any modules defined by LES so we're going to be
-- pretending the routines we defined don't exist.

-- CODE START
function launchBashScript(script)
  local handle = io.popen(
    [[/bin/bash -c ']] .. script .. [[']]
  )
  local retcode = {handle:close()}
  return tonumber(retcode[3])
end

function shouldMigrate()
  local fileHdl = io.open(os.getenv("HOME") .. "/.les/init.lua", "r")
  if fileHdl ~= nil then
      fileHdl:close()
      return launchBashScript(
        [[cmp "${HOME}/.les/init.lua" "]] .. hs.processInfo["bundlePath"] .. [[/Contents/Resources/extensions/hs/les/jumpstart.lua"]]
      ) > 0
  else
      return false
  end
end

if shouldMigrate() == true then
  if
  hs.dialog.blockAlert(
    "Live Enhancement Suite",
[[
LES has detected a mismatched jumpstart script.

This may be because you're upgrading from an older version of LES, if so, this is normal. Would you like to repair your jumpstart script?
]],
    "Yes",
    "No"
  ) == "Yes"
  then
    -- User has accepted repair
    if launchBashScript(
[[
#!/usr/bin/env bash
set -eux
mv "${HOME}/.les/init.lua" "${HOME}/.les/init.lua.bak";
cp "]] .. hs.processInfo["bundlePath"] .. [[/Contents/Resources/extensions/hs/les/jumpstart.lua" "${HOME}/.les/init.lua";
exit 0;
]]
    ) == 0 then
      -- Repair has succeeded
      hs.dialog.blockAlert("Live Enhancement Suite", "LES has successfully repaired the jumpstart script. Please restart LES for these changes to apply.", "Ok", "")
      os.exit()
    else
      -- Repair has failed
      hs.dialog.blockAlert("Live Enhancement Suite", "LES was unable to repair the jumpstart script. Please check permissions for ~/.les or clear the directory and try again.", "Ok", "")
      os.exit()
    end
  else
    -- User has refused repair, prompt for application exit
    if hs.dialog.blockAlert("Live Enhancement Suite", "LES cannot guarantee that it will behave as tested. Would you like to exit LES?", "Yes", "No") == "Yes" then
      -- User has chosen to exit
      os.exit()
    end
    -- User has chosen to continue despite warnings, unsupported
  end
end

-- Un-define functions and free up variables
launchBashScript = nil
shouldMigrate = nil
-- CODE END

-- Actual LESmain code
require("module")
require("helpers")
require("menus.bar")
require("menus.keys.menu")
require("globals.constants")
require("globals.filepaths")
require("proccom")
require("util.io")

module:init()

------------------------
--	Integrity checks  --
------------------------

-- these functions check the if the files nescesary for the script to function; exist.
-- hammerspoon completely spaces out of they don't.
-- I declare them up here because it fits the theme of this section of the script.

function testmenuconfig()
    local var = ioIsFilePresent(GetDataPath("menuconfig.ini")) 

    if var == false then
        if HSMakeQuery(
            programName, [[
                Your menuconfig.ini is missing or corrupt.

                Do you want to restore the default menuconfig?
            ]], "critical"
        ) == true then
            ShellCopy(JoinPaths(BundleResourcePath, MenuConfigFile), ScriptUserPath .. PathDelimiter)
        else
            os.exit()
        end
    end
end

---------------------------
--	Stock menu contents  --
---------------------------

filepath = GetDataPath("resources/strict.txt")
f = io.open(filepath, "r")
if f ~= nil then
    io.close(f)
    _G.stricttimevar = true
else
    _G.stricttimevar = false
end
f = nil
filepath = nil -- sets the strict time setting

-- this is what happens when you hit "readme" in the default plugin menu.

function readme()
    HSPlayAudioFile(JoinPaths(BundleResourceAssetsPath, "readmejingle.wav"))
    HSMakeAlert(programName, [[
        Welcome to the Live Enhancement Suite macOS rewrite developed by @InvertedSilence, @DirectOfficial, with an installer by @actuallyjamez 🐦.
        
        Double right click to open up the custom plug-in menu.
        
        Click on the LES logo in the menu bar to add your own plug-ins, change settings, and read our manual.

        Happy producing : )
    ]])
end

-------------------------------------
--	digesting the menuconfig file  --
-------------------------------------

-- Direct helped make me recreate the original AHK menu file parser in lua before I got started on the project.
-- While it's the first part of the program we made, it's the last thing that worked.
-- This part of the code will always be difficult to comprehend for me, so I figure it's basically impossible to understand you.
-- Turn back while you still can.

-- notice how I'm just declaring function; it's executed later when I run reloadLES().

function buildPluginMenu()

    file = io.open("menuconfig.ini", "r")
    local arr = {}
    for line in file:lines() do
        table.insert(arr, line);
    end -- this part of the code puts the entire config file into a table.

    if pluginArray ~= nil then
        delcount = #pluginArray -- delete plugin list table if there's something in it, to prevent double entries when using reloadLES()
        for i = 0, delcount do
            pluginArray[i] = nil
        end
    end
    if menu ~= nil then
        delcount = #menu -- delete the root menu table if there's something in it, to prevent double entries when using reloadLES()
        for i = 0, delcount do
            menu[i] = nil
        end
    end

    -- Reverses the Array. This could be done inline
    -- but I made it a helper function just in case.
    -- -- Direct
    function Reverse(arr)
        local j, k = 1, #arr

        while j < k do
            arr[j], arr[k] = arr[k], arr[j]

            j = j + 1
            k = k - 1
        end
    end
    -- Reverse the order of the array. 
    print(hs.inspect(arr))
    Reverse(arr)

    readmevar = false

    for i = #arr, 1, -1 -- this part of the code replaces parts of the menu config file with stuff that's easier to parse in lua.
    do
        arr[i] = string.gsub(arr[i], "“", "\"")
        if arr[i] == "—\r" or arr[i] == "-\n" or arr[i] == "—" then
            print("divider line found")
            arr[i] = "--"
            table.insert(arr, i, "--")
        elseif string.len(arr[i]) < 2 and not string.match(arr[i], "%w") then -- this is a bandaid fix preventing lots of empty menu entires 
            table.remove(arr, i)
        elseif arr[i] == nil then
            table.remove(arr, i)
        elseif string.find(arr[i], ";") == 1 then
            table.remove(arr, i)
        elseif string.match(arr[i], "Readme") or string.match(arr[i], "readme") then
            readmevar = true -- I decided to just have the readme always stick on the bottom since it was easier to program and nobody cares anyway :^)
            table.remove(arr, i)
        elseif string.find(arr[i], "%-%-") == 1 then
            table.insert(arr, i, "--")
        elseif string.find(arr[i], "End") then
            table.remove(arr, i)
        elseif string.find(arr[i], "") then
        end
    end

    local subfolderval = 0
    local subfoldername = ""
    local subfolderuponelevel = ""
    subfolderhistory = {}
    pluginArray = {}

    for i = #arr, 1, -1 do
        if string.find(string.sub(arr[i], 1, 1), "/") and not string.find(string.sub(arr[i], 1, 2), "//") and
            not string.find(arr[i], "nocategory") then
            subfoldername = string.gsub(arr[i], '', '')
            table.insert(subfolderhistory, subfoldername)
            subfolderval = 1
            string = subfolderval .. ", " .. subfoldername .. ", " .. "❗️"
            table.insert(pluginArray, string)
            table.insert(pluginArray, string)
            table.remove(arr, i)
        elseif string.find(string.sub(arr[i], 1, 2), "//") then
            table.insert(subfolderhistory, subfoldername)
            subfoldername = string.gsub(arr[i], '', '')
            local _, count = string.gsub(arr[i], "%/", "")
            subfolderval = count
            string = subfolderval .. ", " .. subfoldername .. ", " .. "❗️"
            table.insert(pluginArray, string)
            table.insert(pluginArray, string)
            table.remove(arr, i)
        elseif string.find(string.sub(arr[i], 1, 2), "%.%.") then
            subfoldername = subfolderhistory[subfolderval]
            subfolderval = subfolderval - 1
            -- table.remove(arr, i)
            -- table.insert(arr[i])
        elseif string.find(arr[i], "/nocategory") then
            subfolderval = 0
            table.remove(arr, i)
        else
            string = subfolderval .. ", " .. subfoldername .. ", " .. arr[i]
            table.insert(pluginArray, string)
        end
    end

    print("------pluginarray-----")
    print(hs.inspect(pluginArray))
    print("----------------------")

    function mysplit(inputstr)
        local t = {};
        i = 1
        if inputstr == nil then
            return
        end
        for str in string.gmatch(inputstr, "([^,]+)") do
            t[i] = str
            i = i + 1
        end
        return t
    end

    -- for i = 1, #arr do
    --   print(pluginArray[i])
    -- end

    function RemoveSlashes(string, scope)
        newstring = string:gsub("^%s*(.-)%s*$", "%1")
        newstring = string.sub(newstring, scope + 1)
        return newstring
    end

    local lastLevel = 0
    local level = 0
    lastcatagoryName = "menu"
    scopes = {}

    for i = 1, #pluginArray, 2 do
        if pluginArray[i] == nil then
            table.remove(pluginArray, i)
            goto pls
        end
        if pluginArray[i + 1] == nil then
            table.remove(pluginArray, (i + 1))
            goto pls
        end
        -- print(hs.inspect(scopes))

        local level = tonumber(string.sub(pluginArray[i], 1, 1))

        local thisIndex = mysplit(pluginArray[i])
        local nextIndex = mysplit(pluginArray[i + 1])
        local categoryName = RemoveSlashes(thisIndex[2], level)

        -- RUNS RIGHT AT THE START IF A PLUGIN IS INSERTED FIRST IN THE MENU
        if i == 1 and level == 0 then
            if _G[lastcatagoryName] == nil then
                _G[lastcatagoryName] = {}
            end

            if string.find(string.sub(pluginArray[i], 1, 2), "%-%-") or
                string.find(string.sub(pluginArray[i], 1, 2), "—") then
                table.insert(_G[lastcatagoryName], {title = "-"})
            else
                table.insert(_G[lastcatagoryName], {
                    title = string.sub(thisIndex[3], 2),
                    fn = function()
                        loadPlugin(nextIndex[3])
                    end
                }) -- inserts the first plugin
                print("START. current scope: " .. categoryName .. " level: " .. level .. "item: " .. nextIndex[3])
            end
            -- RUNS RIGHT AT THE START IF A FOLDER IS INSERTED FIRST IN THE MENU
        elseif i == 1 and level == 1 then
            if _G[lastcatagoryName] == nil then
                _G[lastcatagoryName] = {}
            end
            print("START : NEW FOLDER. current scope: " .. categoryName .. " level: " .. level .. "item: " ..
                      nextIndex[3])

            if string.find(nextIndex[3], "❗️") then
                _G[categoryName] = {} -- don't insert the !
            else
                _G[categoryName] = {
                    title = string.sub(thisIndex[3], 2),
                    fn = function()
                        loadPlugin(nextIndex[3])
                    end
                }
            end

            if string.find(string.sub(pluginArray[i], 1, 2), "%-%-") or
                string.find(string.sub(pluginArray[i], 1, 2), "-") then
                table.insert(_G[lastcatagoryName], {title = "-"})
            else
                table.insert(_G[lastcatagoryName], {title = categoryName, menu = _G[categoryName]})
                -- table.insert(_G[lastcatagoryName], {title = string.sub(thisIndex[3],2), fn = function() loadPlugin(nextIndex[3]) end }) -- inserts the first plugin
            end
            table.insert(scopes, lastcatagoryName)
            -- THIS IS IF WE GO BACK TO THE ROOT FOLDER AFTER BEING IN A SUBFOLDER
        elseif level == 0 then
            if string.find(string.sub(thisIndex[3], 1, 4), "%-%-") or
                string.find(string.sub(thisIndex[3], 1, 4), "%—") then
                table.insert(menu, {title = "-"})
            else
                print(string.sub(pluginArray[i], 1, 4))
                table.insert(menu, {
                    title = string.sub(thisIndex[3], 2),
                    fn = function()
                        loadPlugin(nextIndex[3])
                    end
                }) -- inserts the first plugin
                print("RETURN TO ROOT. current scope: " .. categoryName .. " level: " .. level .. "item: " ..
                          nextIndex[3])
            end

            -- Up scope
        elseif level > lastLevel then
            print("UP SCOPE. current scope: " .. categoryName .. " level: " .. level .. "item: " .. nextIndex[3])

            if _G[lastcatagoryName] == nil then
                _G[lastcatagoryName] = {}
            end

            if string.find(nextIndex[3], "❗️") then
                _G[categoryName] = {}
            else
                _G[categoryName] = {
                    title = string.sub(thisIndex[3], 2),
                    fn = function()
                        loadPlugin(nextIndex[3])
                    end
                }
            end

            if string.find(string.sub(pluginArray[i], 1, 2), "%-%-") or
                string.find(string.sub(pluginArray[i], 1, 2), "—") then
                table.insert(_G[lastcatagoryName], {title = "-"})
            else
                table.insert(_G[lastcatagoryName], {title = categoryName, menu = _G[categoryName]}) -- Inserts the new menu
            end
            table.insert(scopes, lastcatagoryName)

            -- Same scope
        elseif level == lastLevel and categoryName == lastcatagoryName then

            print("SAME SCOPE. current scope: " .. categoryName .. " level: " .. level .. "item: " .. nextIndex[3])
            if string.find(pluginArray[i], "%-%-") or string.find(pluginArray[i], "—") then
                table.insert(_G[categoryName], {title = "-"})
            else
                table.insert(_G[categoryName], {
                    title = string.sub(thisIndex[3], 2),
                    fn = function()
                        loadPlugin(nextIndex[3])
                    end
                }) -- inserts plugin 
            end

            -- Same scope new folder
        elseif level == lastLevel and categoryName ~= lastcatagoryName then
            print("scopes: " .. scopes[level])
            table.remove(scopes, level + 1)
            if _G[categoryName] == nil then
                _G[categoryName] = {}
            end

            if string.find(string.sub(pluginArray[i], 1, 2), "%-%-") or
                string.find(string.sub(pluginArray[i], 1, 2), "—") then
                table.insert(_G[scopes[level]], {title = "-"})
            else
                table.insert(_G[scopes[level]], {title = categoryName, menu = _G[categoryName]}) -- Inserts the new menu
            end

            print("SAME SCOPE NEW FOLDER. current scope: " .. categoryName .. " level: " .. level .. "item: " ..
                      nextIndex[3])

            -- Down scope with new folder
        elseif level < lastLevel and categoryName ~= lastcatagoryName then
            print("DOWN SCOPE NEW FOLDER. current scope: " .. categoryName .. " level: " .. level .. "item: " ..
                      nextIndex[3])
            print("scopes: " .. scopes[level])
            if scopes[level] == "menu" then
                scopes = {"menu"}
            end
            -- table.insert(scopes, lastcatagoryName)
            if _G[categoryName] == nil then
                _G[categoryName] = {}
                table.insert(_G[scopes[level]], {title = categoryName, menu = _G[categoryName]}) -- Inserts the new menu
            end

            if string.find(string.sub(pluginArray[i], 1, 2), "%-%-") or
                string.find(string.sub(pluginArray[i], 1, 2), "—") then
                table.insert(_G[categoryName], {title = "-"})
            else
                if string.find(nextIndex[3], "❗️") then
                    table.insert(_G[categoryName], {}) -- inserts plugin
                else
                    table.insert(_G[categoryName], {
                        title = string.sub(thisIndex[3], 2),
                        fn = function()
                            loadPlugin(nextIndex[3])
                        end
                    }) -- inserts plugin
                end
            end

            -- Down scope
        elseif level < lastLevel and categoryName == lastcatagoryName then
            print("DOWN SCOPE. current scope: " .. categoryName .. " level: " .. level .. "item: " .. nextIndex[3])
            if _G[categoryName] == nil then
                _G[categoryName] = {}
            end
            if string.find(string.sub(pluginArray[i], 1, 2), "%-%-") or
                string.find(string.sub(pluginArray[i], 1, 2), "—") then
                table.insert(_G[categoryName], {title = "-"})
            else
                table.insert(_G[categoryName], {
                    title = string.sub(thisIndex[3], 2),
                    fn = function()
                        loadPlugin(nextIndex[3])
                    end
                }) -- inserts plugin
            end
        end
        lastLevel = level
        -- this conditional basically checks if we are 'home' and if we are
        -- then we last category = menu.
        if categorycount == nil then
            categorycount = 0 -- 0 because the count is increased to 1 by the first item causing the first entry to be nil (it's a stupid workaround)
            categoryhistory = {}
        end

        if lastLevel == 0 then
            lastcatagoryName = "menu"
        else
            if lastcatagoryName ~= nil then -- this part of the code keeps track of all the subfolder names, so they can be cleared later; preventing double entires on reloadLES()
                if lastcatagoryName ~= categoryName then
                    categorycount = (categorycount + 1)
                end
            end
            lastcatagoryName = categoryName
            categoryhistory[categorycount] = lastcatagoryName
        end

        ::pls::
    end

    if readmevar == true then
        -- table.insert(menu, {title = "-"})
        table.insert(menu, {
            title = "read me",
            fn = function()
                readme()
            end
        })
    end

    categoryName = nil
    lastcatagoryName = nil
    lastlevel = nil
    level = nil
    scope = nil
    categorycount = nil
end

function clearcategories()
    -- this part of the code goes back through the folder structure history created around line 585 to clear all folders it before rebuilding the menu again. 
    -- this prevents double entries from showing up after reloadLES() was executed.
    if categoryhistory ~= nil then
        print("category history exists")
        for i = 1, #categoryhistory, 1 do
            _G[categoryhistory[i]] = nil
        end
        categoryhistory = nil
    end
end

---------------------------------
--	Creating menubar contents  --
---------------------------------

function buildMenuBar() -- this function makes the menu bar happen, the one that pops up when you click the icon in the top right.
    if LESmenubar ~= nil then
        LESmenubar:delete()
    end -- this is me trying to clear it properly, but as experience has shown; hammerspoon doesn't properly garbage collect these well so I'm not sure if it even matters.
    LESmenubar = hs.menubar.new()
    LESmenubar:setMenu(getMenuBar(_G.enabledebug == 1, _G.stricttimevar))
    if _G.texticon == 1 then
        LESmenubar:setTitle("LES")
    else
        LESmenubar:setIcon(BundleResourcePath .. "/assets/osxTrayIcon.png", true) -- cool icon :sunglasses:
    end
end

function rebuildRcMenu()
    -- This function rebuilds the right click menus inside ableton.
    -- The right click menu's are actually just menu bar items, but they're invisible.
    -- Both the pianomenu and the plugin menu are (re)loaded.
    if pluginMenu ~= nil then
        pluginMenu:delete()
    end -- this is me trying to clear it properly, but as experience has shown; hammerspoon doesn't properly garbage collect these well so I'm not sure if it even matters.
    pluginMenu = hs.menubar.new()
    pluginMenu:setMenu(menu)
    pluginMenu:setTitle("LES")
    pluginMenu:removeFromMenuBar() -- it seeems to stick around even when I don't want it to :-(

    if pianoMenu ~= nil then
        pianoMenu:delete()
    end -- this is me trying to clear it properly, but as experience has shown; hammerspoon doesn't properly garbage collect these well so I'm not sure if it even matters.
    pianoMenu = hs.menubar.new()
    pianoMenu:setMenu(ShiftDoubleRightClickMenu)
    pianoMenu:setTitle("Piano")
    pianoMenu:removeFromMenuBar() -- it seeems to stick around even when I don't want it to :-(
end

-----------------
--	Reloading  --
-----------------

function cheats()
    -- This is the function for the cheats menu. I didn't recreate all of the cheets from the windows version, but I did recreate some of them.
    -- it needs to be up here, because it's used in the reloadLES() routine. Functions need to be declared before they're used.

    if _G.enabledebug == 1 then
        down1, down2 = false, true
        -- this "dingodango" thing keeps track of the user doubletapping both shift keys. cheatmenu() is run when you do.
        dingodango = hs.eventtap.new({hs.eventtap.event.types.flagsChanged, hs.eventtap.event.types.keyDown},
            function(e)
                local flag = e:rawFlags()
                -- print(flag)
                if flag == 131334 and down1 == false and down2 == true then
                    print("doubleshift press 1")
                    press1 = hs.timer.secondsSinceEpoch()
                    down1 = true
                    down2 = false
                    if press2 ~= nil then
                        if (press1 - press2) < 0.2 then
                            cheatmenu()
                        end
                    end
                elseif flag == 131334 and down1 == true and down2 == false then
                    print("doubleshift press 2")
                    press2 = hs.timer.secondsSinceEpoch()
                    down1 = false
                    down2 = true
                    if (press2 - press1) < 0.2 then
                        cheatmenu()
                    end
                end
            end):start()
    else
        if dingodango then
            dingodango:stop()
        end
    end
end

function reloadLES()
    -- this function is the heart of the program, reloadLES() (re)builds all of the user configuration.
    -- this is nescesary because restarting hammerspoon is frustratingly slow compared to restarting ahk; so instead I'm manually clearing and rewriting everything when you hit "reload".
    -- reloadLES() is also run a single time on startup to build everything for the first time, standardizing the routine.
    -- all of the functions used here are explained in detail up above.

    clearcategories()
    if pluginMenu then
        pluginMenu = nil
    end
    if pianoMenu then
        pianoMenu = nil
    end
    testmenuconfig()
    settingsManager:init()
    settingsManager:parse()
    settingsManager:map()
    buildPluginMenu()
    buildMenuBar()
    rebuildRcMenu()
    if _G.addtostartup == 1 then -- this thing adds a startup daemon for LES when enabled and removes it when you turn it off.
        print("startup = true")
        hs.autoLaunch(true)
        os.execute([[launchctl load "]] .. BundleResourcePath .. [[/assets/live.enhancement.suite.plist"]])
    else
        print("startup = false")
        hs.autoLaunch(false)
        os.execute([[launchctl unload "]] .. BundleResourcePath .. [[/assets/live.enhancement.suite.plist"]])
    end
    -- pluginMenu:removeFromMenuBar() -- somehow if stuff doesn't properly get removed
    -- pianoMenu:removeFromMenuBar()
    cheats()
end

function quickreload()
    -- this quickreload function is used by the dynamicreload feature. The function is executed right before opening the plugin menu, causing the contents to refresh automatically.
    -- it's shorter, smaller, and thus lighter than the full fat reloadLES() function (which became kind of bloaty over time).
    clearcategories()
    if pluginMenu then
        pluginMenu = nil
    end
    if pianoMenu then
        pianoMenu = nil
    end
    testmenuconfig()
    buildPluginMenu()
    rebuildRcMenu()
end

reloadLES() -- when the script reaches this point, reloadLES is executed for a first time - finally actually doing all the stuff up above.

function InstallInsertWhere()
    if HSMakeQuery(
        programName, [[
            InsertWhere is a Max For Live companion device developed by Mat Zo.

            InsertWhere allows you to change the position where plugins are autoinserted after using the LES plugin menu.

            Once loaded, it will allow you to switch between these settings:

            - Autoadd plugins before the one you have selected
            - Autoadd plugins after the the one you have selected
            - Always autoadd plugins at the end of the chain like normal

            To activate InsertWhere, place a single instance of the device on the master channel in your project and choose your desired setting.

            Do you want to install the InsertWhere M4L plugin?
        ]]
    ) == true then
        HSMakeAlert(programName, [[
            Please select the location where you want LES to extract the InsertWhere companion plugin.
            
            Recommended: Ableton User Library
        ]], true)
        extractLocation = hs.dialog.chooseFileOrFolder("Please select the location to extract InsertWhere:",
            "~/Music/Ableton", false, true, false)
        if extractLocation ~= nil then
            ShellCopy(JoinPaths(BundleResourceAssetsPath, "InsertWhere.amxd"), extractLocation["1"])
            HSMakeAlert(programName, [[
                Success!!

                For extra ease of use, include InsertWhere in your default template.

                For more information on InsertWhere, visit the documentation website linked under the "Manual 📖" button in the tray.

                Thank you Mat Zo for making this amazing device!
            ]], true)
        end
    end
end

-----------------------
--	Macro shortcuts  --
-----------------------

-- this is direct's hyper. it opens the plugin menu. It's kept in for fallback purposes.
-- the difference between hs.hotkey is that it blocks the original input; hs.eventtap.event does not.

-- This is my current fallback because I cannot seem to get
-- the double right clicking working properly yet. - Direct
hyper = {"cmd", "shift"}
directshyper = hs.hotkey.bind(hyper, "H", function()
    spawnPluginMenu()
end)

hyper3 = {"cmd", "alt"}
hs.hotkey.bind(hyper3, "S", function()
end)

-- buplicate shortcut
buplicate = hs.hotkey.bind({"cmd"}, "B", function()
    if buplicatelastshortcut == 0 or buplicatelastshortcut == nil then
        selectLiveMenuItem("Duplicate")
        selectLiveMenuItem("Duplicate")
        selectLiveMenuItem("Duplicate")
        selectLiveMenuItem("Duplicate")
        selectLiveMenuItem("Duplicate")
        selectLiveMenuItem("Duplicate")
        selectLiveMenuItem("Duplicate")

    elseif buplicatelastshortcut == 1 then
        selectLiveMenuItem("Duplicate")
        selectLiveMenuItem("Duplicate")
        selectLiveMenuItem("Duplicate")
        selectLiveMenuItem("Duplicate")
        selectLiveMenuItem("Duplicate")
        selectLiveMenuItem("Duplicate")
        selectLiveMenuItem("Duplicate")
        selectLiveMenuItem("Duplicate")
    end
    buplicatelastshortcut = 1
end)

-- since eventtap.events seems to use quite a bit of CPU on lower end models, I've decided to try and condense a bunch of such shortcuts into this section.
-- the advantage of this approach is, unlike hs.hotkey, that it sends the original input still.
-- it also allows you to trigger actions on the key down or key up event only, which is nice. 

-- I also tend to prefer tasking the menubar instead of using a cmd keystroke. There seems to be a system bound limit on how fast you can send shortcuts.
-- by using the menubar instead I'm able to bypass this somehow

_G.debounce = false
down12, down22 = false, true

_G.quickmacro = hs.eventtap.new({ -- this is the hs.eventtap event that contains all of the macro shortcuts.
hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp, hs.eventtap.event.types.leftMouseDown,
hs.eventtap.event.types.leftMouseUp}, function(event)
    local keycode = event:getKeyCode()
    local mousestate = event:getButtonState(0)
    local eventtype = event:getType()
    local clickState = hs.eventtap.event.properties.mouseEventClickState

    backspacekk = hs.keycodes.map["delete"]

    -- macro for automatically disabling loop on clips
    if _G.disableloop == 1 then
        if keycode == hs.keycodes.map["M"] and hs.eventtap.checkKeyboardModifiers().shift and
            hs.eventtap.checkKeyboardModifiers().cmd then
            local hyper2 = {"cmd", "shfit"}
            hs.eventtap.keyStroke(hyper2, "J")
        end
    end

    if keycode == hs.keycodes.map["G"] and hs.eventtap.checkKeyboardModifiers().alt and eventtype ==
        hs.eventtap.event.types.keyDown then
        point = hs.mouse.getAbsolutePosition()
        hs.eventtap.middleClick(point, 0)
    end

    -- envelope mode macro
    if keycode == hs.keycodes.map["E"] and hs.eventtap.checkKeyboardModifiers().alt then
        _G.dimensions = getLiveHsAppObj():mainWindow():frame()
        -- print("top left: " .. _G.dimensions.x .. " & " .. _G.dimensions.y)
        -- print("top right: " .. (_G.dimensions.x + _G.dimensions.w) .. " & " .. _G.dimensions.y)
        -- print("bottom left: " .. _G.dimensions.x .. " & " .. (_G.dimensions.y + _G.dimensions.h))

        -- I'm trying to use maths to consistenly figure out where the envelope button might be.
        -- I fire a laser of diagonal clicks, hoping to hit the button. I finetuned these values to the point that it works pretty well.

        local prepoint = {}
        prepoint = hs.mouse.getAbsolutePosition()
        prepoint["__luaSkinType"] = nil

        local coolvar5 = (_G.dimensions.x + 43)
        local coolvar4 = (_G.dimensions.y + _G.dimensions.h - 37)

        local postpoint = {}
        postpoint["x"] = coolvar5
        postpoint["y"] = coolvar4
        for i = 1, 5, 1 do
            hs.eventtap.leftClick(postpoint, 0)
            postpoint["x"] = postpoint["x"] + 18
            postpoint["y"] = postpoint["y"] - 18
            -- print(hs.inspect(postpoint))
        end
        postpoint["x"] = (_G.dimensions.x + 51)
        postpoint["y"] = (_G.dimensions.y + _G.dimensions.h - 47)
        hs.eventtap.leftClick(postpoint, 0)
        hs.eventtap.event.newMouseEvent(hs.eventtap.event.types["leftMouseUp"], prepoint):post()
        -- print(hs.inspect("prepoint: " .. prepoint))
    end

    -- save as new version
    if _G.saveasnewver == 1 then
        if keycode == hs.keycodes.map["S"] and hs.eventtap.checkKeyboardModifiers().alt and
            hs.eventtap.checkKeyboardModifiers().cmd then
            if _G.debounce == false then
                _G.debounce = true
                local hyper2 = {"cmd", "shift"}
                local mainwindowname = getLiveHsAppObj():mainWindow():title()
                -- print(mainwindowname)
                local projectname = (mainwindowname:gsub("%s%s%[.*", "")) -- use Gsub to get project name from main window title
                local newname = nil

                if projectname == "Untitled" and o == nil then -- dialog box that warns you when you save as new version on an untitled project
                    if astBlockingQuery(
                        programName,
                        [[Your project name is "Untitled"\nAre you sure you want to save it as a new version?]]
                    ) == true then
                        hs.eventtap.keyStroke(hyper2, "S")
                        if astSleep(2) == true then
                            debounce = false
                        end
                        return
                    end
                end

                if string.find(projectname, "_%d") then -- does the project already have a version syntax?
                    local version = (projectname:gsub(".*(.*)_", "%1")) -- remove everything after the last "_"
                    local name = (projectname:gsub("(.*)_.*", "%1")) -- remove everything prior to the last "_"

                    if string.find(version, "%.") and string.find(version, "%a") then -- test if the current version syntax has both a decimal and a letter
                        local everythingafterdecimal = version:gsub(".*%.", "") -- process things after decimal and pre decimal 
                        everythingafterdecimal = everythingafterdecimal:gsub("%a", "1")
                        version = version:gsub("%..*", "." .. everythingafterdecimal)
                    end

                    if string.find(version, "%.") then -- if string has a decimal point, round it up
                        newver = math.ceil(version)
                    else
                        newver = (version + 1) -- if string doesn't have a decimal point, add 1
                        newver = math.floor(newver)
                    end
                    newname = name .. "_" .. newver
                else
                    newname = projectname .. "_2"
                end

                -- hs.osascript.applescript([[
                -- tell application "System Events" to tell process "Live"
                --   ignoring application responses
                --     click menu item "Save Live Set As..." in menu 1 in menu bar item "File" in menu bar 1
                --   end ignoring
                -- end tell
                -- ]])

                -- I used to use applescript for this, but it turned out hs.application.selectMenuItem was better.

                selectLiveMenuItem("Save Live Set As")

                astSleep(0.18)

                hs.eventtap.keyStrokes(newname)
                hs.eventtap.keyStroke({}, "return")

                if astSleep(2.5) == true then
                    debounce = false
                end
            end
        end
    end

    -- macro for closing currently focussed plugin window
    if _G.enableclosewindow ~= 0 then
        if keycode == hs.keycodes.map["W"] and hs.eventtap.checkKeyboardModifiers().cmd and
            not hs.eventtap.checkKeyboardModifiers().alt then
            local mainwindowname = nil
            mainwindowname = getLiveHsAppObj():mainWindow()
            focusedWindow = hs.window.frontmostWindow()
            if mainwindowname ~= focusedWindow then
                focusedWindow:close()
            end
        end

        -- macro for closing all plugin windows
        if keycode == hs.keycodes.map["W"] and hs.eventtap.checkKeyboardModifiers().cmd and
            hs.eventtap.checkKeyboardModifiers().alt or keycode == hs.keycodes.map["escape"] and
            hs.eventtap.checkKeyboardModifiers().cmd then
            local allwindows = getLiveHsAppObj():allWindows()
            local mainwindowname = nil
            mainwindowname = getLiveHsAppObj():mainWindow()
            for i = 1, #allwindows, 1 do
                if allwindows[i] ~= mainwindowname then
                    allwindows[i]:close()
                end
            end
        end
    end

    -- macro for adding a locator in the playlist
    if altgrmarker == 1 then
        if keycode == hs.keycodes.map["L"] and hs.eventtap.checkKeyboardModifiers().alt and eventtype ==
            hs.eventtap.event.types.keyDown and not hs.eventtap.checkKeyboardModifiers().cmd then
            print("marker macro pressed")
            -- hs.osascript.applescript([[
            --   tell application "Live" to activate
            --   tell application "System Events" to tell process "Live"
            --     ignoring application responses
            --       click menu item "Add Locator" in menu 1 in menu bar item "Create" in menu bar 1
            --       key code ]] .. backspacekk .. "\n" ..
            --     [[end ignoring
            --   end tell
            -- ]])

            -- I used to use applescript for this, but it turned out hs.application.selectMenuItem was better.

            selectLiveMenuItem("Add Locator")

            hs.eventtap.keyStroke({}, "delete", 0)
        end
    else
        if keycode == hs.keycodes.map["L"] and hs.eventtap.checkKeyboardModifiers().shift and eventtype ==
            hs.eventtap.event.types.keyDown then
            print("marker macro pressed")
            -- hs.osascript.applescript([[
            --   tell application "Live" to activate
            --   tell application "System Events" to tell process "Live"
            --     ignoring application responses
            --       click menu item "Add Locator" in menu 1 in menu bar item "Create" in menu bar 1
            --       key code ]] .. backspacekk .. "\n" ..
            --     [[end ignoring
            --   end tell
            -- ]])

            -- I used to use applescript for this, but it turned out hs.application.selectMenuItem was better.
            selectLiveMenuItem("Add Locator")

            hs.eventtap.keyStroke({}, "delete", 0)
        end
    end

    -- Absolute Duplicate
    if _G.absolutereplace ~= 0 then
        if ctrlabsoluteduplicate == 1 then
            if keycode == hs.keycodes.map["D"] and hs.eventtap.checkKeyboardModifiers().ctrl and
                hs.eventtap.checkKeyboardModifiers().cmd and eventtype == hs.eventtap.event.types.keyUp then
                -- hs.osascript.applescript([[tell application "Live" to activate
                --   tell application "System Events" to tell process "live"
                --   ignoring application responses
                --     click menu item "Copy" in menu 1 in menu bar item "Edit" in menu bar 1
                --     click menu item "Duplicate" in menu 1 in menu bar item "Edit" in menu bar 1
                --     key code ]] .. backspacekk .. "\n" ..
                --     [[click menu item "Paste" in menu 1 in menu bar item "Edit" in menu bar 1
                --   end ignoring
                -- end tell]])

                -- I used to use applescript for this, but it turned out hs.application.selectMenuItem was better.
                selectLiveMenuItem("Copy")
                selectLiveMenuItem("Duplicate")
                selectLiveMenuItem("Delete")
                selectLiveMenuItem("Paste")
            end
        else
            if keycode == hs.keycodes.map["D"] and hs.eventtap.checkKeyboardModifiers().alt and
                hs.eventtap.checkKeyboardModifiers().cmd and eventtype == hs.eventtap.event.types.keyUp then
                -- hs.osascript.applescript([[tell application "Live" to activate
                --   tell application "System Events" to tell process "live"
                --   ignoring application responses
                --     click menu item "Copy" in menu 1 in menu bar item "Edit" in menu bar 1
                --     click menu item "Duplicate" in menu 1 in menu bar item "Edit" in menu bar 1
                --     key code ]] .. backspacekk .. "\n" ..
                --     [[click menu item "Paste" in menu 1 in menu bar item "Edit" in menu bar 1
                --   end ignoring
                -- end tell]])

                -- I used to use applescript for this, but it turned out hs.application.selectMenuItem was better.

                selectLiveMenuItem("Copy")
                selectLiveMenuItem("Duplicate")
                selectLiveMenuItem("Delete")
                selectLiveMenuItem("Paste")
            end
        end

        if keycode == hs.keycodes.map["V"] and hs.eventtap.checkKeyboardModifiers().alt and
            hs.eventtap.checkKeyboardModifiers().cmd and eventtype == hs.eventtap.event.types.keyUp then
            -- hs.osascript.applescript([[tell application "Live" to activate
            --   tell application "System Events" to tell process "live"
            --   ignoring application responses
            --     click menu item "Paste" in menu 1 in menu bar item "Edit" in menu bar 1
            --     key code ]] .. backspacekk .. "\n" ..
            --     [[click menu item "Paste" in menu 1 in menu bar item "Edit" in menu bar 1
            --   end ignoring
            -- end tell]])

            -- I used to use applescript for this, but it turned out hs.application.selectMenuItem was better.

            selectLiveMenuItem("Paste")
            selectLiveMenuItem("Delete")
            selectLiveMenuItem("Paste")
        end
    end

    if keycode ~= hs.keycodes.map["B"] or eventtype == hs.eventtap.event.types.leftMouseDown and buplicatelastshortcut ==
        1 then
        buplicatelastshortcut = 0
    end

    if _G.double0todelete == 1 then
        if keycode == hs.keycodes.map["0"] then -- double zero to delete
            if down12 == false and down22 == true then
                press12 = hs.timer.secondsSinceEpoch()
                down12 = true
                down22 = false
                if press22 ~= nil then
                    if (press12 - press22) < 0.05 then
                        hs.eventtap.keyStroke({}, hs.keycodes.map["delete"], 0)
                        press12 = nil
                        press22 = nil
                    end
                end
            elseif down12 == true and down22 == false then
                press22 = hs.timer.secondsSinceEpoch()
                down12 = false
                down22 = true
                if press12 ~= nil then
                    if (press22 - press12) < 0.05 then
                        hs.eventtap.keyStroke({}, hs.keycodes.map["delete"], 0)
                        press12 = nil
                        press22 = nil
                    end
                end
            end
        end
    end

    if keycode == hs.keycodes.map["X"] and hs.eventtap.checkKeyboardModifiers().alt and eventtype ==
        hs.eventtap.event.types.keyDown then -- clear track
        if firstDown ~= nil or secondDown ~= nil then
            timeRMBTime, firstDown, secondDown = 0, false, true
        end
        firstRightClick:stop()
        local point = {}
        point = hs.mouse.getAbsolutePosition()
        point["__luaSkinType"] = nil
        hs.eventtap.rightClick(point, 0)

        hs.eventtap.keyStroke({}, "down", 0);
        hs.eventtap.keyStroke({}, "down", 0);
        hs.eventtap.keyStroke({}, "down", 0);
        hs.eventtap.keyStroke({}, "down", 0);
        hs.eventtap.keyStroke({}, "down", 0);
        hs.eventtap.keyStroke({}, "down", 0)
        hs.eventtap.keyStroke({}, "down", 0);
        hs.eventtap.keyStroke({}, "down", 0);
        hs.eventtap.keyStroke({}, "down", 0);
        hs.eventtap.keyStroke({}, "down", 0);
        hs.eventtap.keyStroke({}, "down", 0);
        hs.eventtap.keyStroke({}, "down", 0)
        hs.eventtap.keyStroke({}, "return", 0)
        hs.eventtap.keyStroke({}, "delete", 0)
        firstRightClick:start()
    end

    if keycode == hs.keycodes.map["C"] and hs.eventtap.checkKeyboardModifiers().alt and eventtype ==
        hs.eventtap.event.types.keyDown then -- colour track
        if firstDown ~= nil or secondDown ~= nil then
            timeRMBTime, firstDown, secondDown = 0, false, true
        end
        firstRightClick:stop()
        local point = {}
        point = hs.mouse.getAbsolutePosition()
        point["__luaSkinType"] = nil
        hs.eventtap.rightClick(point, 0)

        hs.eventtap.keyStroke({}, "up", 0)
        hs.eventtap.keyStroke({}, "up", 0)
        hs.eventtap.keyStroke({}, "return", 0)
        firstRightClick:start()
    end

    if vstshortcuts == 1 then
        if keycode == hs.keycodes.map["Z"] and hs.eventtap.checkKeyboardModifiers().cmd and
            not hs.eventtap.checkKeyboardModifiers().shift and eventtype == hs.eventtap.event.types.keyDown then -- pro-q 3 undo
            windowname = hs.window.focusedWindow():title()
            if string.lower(string.gsub(windowname, "(.*)/.*$", "%1")) == "fabfilter pro-q 3" and scaling == 0 then
                windowframe = hs.window.focusedWindow():frame()
                prepoint = hs.mouse.getAbsolutePosition()
                postpoint = {}
                quotient = windowframe.w / windowframe.h
                quotient = string.format("%.4f", quotient) -- I used a bunch of string.format here because for some reason the normal way didn't work?????????? no idea why

                if quotient == string.format("%.4f", 2.0512820512821) then -- mini scaling
                    fraction = 13 / 30
                end
                if quotient == string.format("%.4f", 1.6112266112266) then -- small scaling
                    fraction = 12 / 30
                end
                if quotient == string.format("%.4f", 1.6187050359712) then -- medium scaling
                    fraction = 12 / 31
                end
                if quotient == string.format("%.4f", 1.625) then -- large scaling
                    fraction = 12 / 30
                end
                if quotient == string.format("%.4f", 1.6304347826087) then -- extra large scaling
                    fraction = 12 / 29
                end
                if fraction == nil then
                    HSMakeAlert(programName, [[
                        If you're seeing this, it means that Midas didn't properly think about the way VST plugins deal with scaling at your current display resolution.

                        Perhaps you have the plugin (or your OS) set to a custom scaling amount?

                        It is recommended to disable the VST specific shortcuts in the settings.ini if you want to continue to use custom scaling.

                        These shortcuts will be disabled until LES is reloaded.
                    ]], true, "warning")
                    scaling = 1
                    goto yeet
                end

                postpoint["x"] = windowframe.x + (windowframe.w * fraction)
                postpoint["y"] = windowframe.y + titlebarheight() + 20
                hs.eventtap.leftClick(postpoint, 0)
                hs.eventtap.event.newMouseEvent(hs.eventtap.event.types["leftMouseUp"], postpoint):post()

                hs.eventtap.event.newMouseEvent(hs.eventtap.event.types["leftMouseUp"], prepoint):post() -- a disconnected left click up event is faster than hs.mouse.setAbsolutePosition()
                fraction = nil
                quotient = nil
            end
        end

        if keycode == hs.keycodes.map["Z"] and hs.eventtap.checkKeyboardModifiers().cmd and
            hs.eventtap.checkKeyboardModifiers().shift and eventtype == hs.eventtap.event.types.keyDown then -- pro-q 3 redo
            windowname = hs.window.focusedWindow():title()
            if string.lower(string.gsub(windowname, "(.*)/.*$", "%1")) == "fabfilter pro-q 3" and scaling == 0 then
                windowframe = hs.window.focusedWindow():frame()
                prepoint = hs.mouse.getAbsolutePosition()
                postpoint = {}
                quotient = windowframe.w / windowframe.h
                quotient = string.format("%.4f", quotient) -- I used a bunch of string.format here because for some reason the normal way didn't work?????????? no idea why

                if quotient == string.format("%.4f", 2.0512820512821) then -- mini scaling
                    fraction = 14 / 30
                end
                if quotient == string.format("%.4f", 1.6112266112266) then -- small scaling
                    fraction = 13 / 30
                end
                if quotient == string.format("%.4f", 1.6187050359712) then -- medium scaling
                    fraction = 13 / 31
                end
                if quotient == string.format("%.4f", 1.625) then -- large scaling
                    fraction = 12 / 28
                end
                if quotient == string.format("%.4f", 1.6304347826087) then -- extra large scaling
                    fraction = 13 / 30
                end
                if fraction == nil then
                    HSMakeAlert(programName, [[
                        If you're seeing this, it means that Midas didn't properly think about the way VST plugins deal with scaling at your current display resolution.

                        Perhaps you have the plugin (or your OS) set to a custom scaling amount?

                        It is recommended to disable the VST specific shortcuts in the settings.ini if you want to continue to use custom scaling.

                        These shortcuts will be disabled until LES is reloaded.
                    ]], true, "warning")
                    scaling = 1
                    goto yeet
                end

                postpoint["x"] = windowframe.x + (windowframe.w * fraction)
                postpoint["y"] = windowframe.y + titlebarheight() + 20
                hs.eventtap.leftClick(postpoint, 0)
                hs.eventtap.event.newMouseEvent(hs.eventtap.event.types["leftMouseUp"], postpoint):post()

                hs.eventtap.event.newMouseEvent(hs.eventtap.event.types["leftMouseUp"], prepoint):post() -- a disconnected left click up event is faster than hs.mouse.setAbsolutePosition()
                fraction = nil
                quotient = nil
            end
        end
        ::yeet::
    end

end):start() -- starts the eventtap listener containing all of the keyboard shortcuts.

_G.pausebutton = hs.eventtap.new({hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp}, function(event)
    local keycode = event:getKeyCode()
    local eventtype = event:getType()

    if keycode == hs.keycodes.map["1"] and hs.eventtap.checkKeyboardModifiers().cmd and
        hs.eventtap.checkKeyboardModifiers().shift and eventtype == hs.eventtap.event.types.keyDown then
        if threadsenabled == true then
            hs.alert.show("LES paused")
            disablemacros()
            appwatcher:stop()
        else
            hs.alert.show("LES unpaused")
            enablemacros()
            appwatcher:start()
        end
    end
end):start()

----------------------------------
--  VST shortcuts as hs.hotkey  --
----------------------------------

-- hs.hotkey shortcuts replace the user's original input; so I use a combination of hs.application.watcher and hs.timer to enable them only when nescesary.

if vstshortcuts == 1 then
    undo = hs.hotkey.bind({"cmd"}, "z", function() -- kick 2 undo
        windowname = hs.window.focusedWindow():title()
        if string.lower(string.gsub(windowname, "(.*)/.*$", "%1")) == "kick 2" then
            windowframe = hs.window.focusedWindow():frame()
            prepoint = hs.mouse.getAbsolutePosition()
            postpoint = {}
            postpoint["x"] = windowframe.x + (windowframe.w / 3.40)
            postpoint["y"] = windowframe.y + titlebarheight() + 85

            hs.eventtap.middleClick(postpoint, 12000) -- for some reason middle click works but not left click
            -- hs.eventtap.event.newMouseEvent(hs.eventtap.event.types["leftMouseUp"], postpoint):post()
            hs.timer.usleep(12000)
            hs.eventtap.event.newMouseEvent(hs.eventtap.event.types["leftMouseUp"], prepoint):post() -- a disconnected left click up event is faster than hs.mouse.setAbsolutePosition()
        end
    end)

    redo = hs.hotkey.bind({"cmd", "shift"}, "z", function() -- kick 2 redo
        windowname = hs.window.focusedWindow():title()
        if string.lower(string.gsub(windowname, "(.*)/.*$", "%1")) == "kick 2" then
            windowframe = hs.window.focusedWindow():frame()
            prepoint = hs.mouse.getAbsolutePosition()
            postpoint = {}
            postpoint["x"] = windowframe.x + (windowframe.w / 3.19)
            postpoint["y"] = windowframe.y + titlebarheight() + 85

            hs.eventtap.middleClick(postpoint, 12000) -- for some reason middle click works but not left click
            -- hs.eventtap.event.newMouseEvent(hs.eventtap.event.types["leftMouseUp"], postpoint):post()
            hs.timer.usleep(12000)
            hs.eventtap.event.newMouseEvent(hs.eventtap.event.types["leftMouseUp"], prepoint):post()
        end
    end)
end

-----------------------------
--  Right CLicking & Menus --
-----------------------------

function spawnPluginMenu() -- spawns and moves the invisible menu bar menu to the mouse location.
    pluginMenu:popupMenu(hs.mouse.getAbsolutePosition())
end

function spawnPianoMenu() -- spawns and moves the invisible menu bar menu to the mouse location.
    pianoMenu:popupMenu(hs.mouse.getAbsolutePosition())
end

function getABSTime()
    return hs.timer.absoluteTime()
end

function nanoToSec(nanoseconds)
    seconds = nanoseconds * 1000000000
    return seconds
end

-- The macOS system menu right click behavior is to open the
-- menu on the mouseDown event. If we trigger our action on
-- that event as well the system menu will delay being opened
-- and essentially store the action until our menu closes. We
-- must trigger our event on the mouse up event. -- Direct

timeRMBTime, firstDown, secondDown = 0, false, true

timeFrame = hs.eventtap.doubleClickInterval()

down13 = false
down23 = true
firstRightClick = hs.eventtap.new({hs.eventtap.event.types.rightMouseDown, hs.eventtap.event.types.rightMouseUp},
    function(event)

        -- this is the old double right click routine

        -- if event:getType() == hs.eventtap.event.types.rightMouseDown then
        --   if down13 == false and down23 == true then
        --     print("rclick 1")
        --     press13 = hs.timer.secondsSinceEpoch()
        --     down13 = true
        --     down23 = false
        --     if press23 ~= nil then
        --       if (press13 - press23) < 0.18 then
        --         if _G.dynamicreload == 1 then
        --           quickreload()
        --         end
        --         if _G.pressingshit == true then
        --           spawnPianoMenu()
        --           return
        --         else
        --           spawnPluginMenu()
        --           return
        --         end
        --       end
        --     end
        --   elseif down13 == true and down23 == false then
        --     print("rclick 2")
        --     press23 = hs.timer.secondsSinceEpoch()
        --     down13 = false
        --     down23 = true
        --     if press13 ~= nil then
        --       if (press23 - press13) < 0.18 then
        --         if _G.dynamicreload == 1 then
        --           quickreload()
        --         end
        --         if _G.pressingshit == true then
        --           spawnPianoMenu()
        --           return
        --         else
        --           spawnPluginMenu()
        --           return
        --         end
        --       end
        --     end
        --   end
        -- end

        -- if event:getType() == hs.eventtap.event.types.rightMouseUp then

        if timeRMBTime == nil then
            timeRMBTime, firstDown, secondDown = 0, false, true
        end

        if (hs.timer.secondsSinceEpoch() - timeRMBTime) > timeFrame then
            timeRMBTime, firstDown, secondDown = 0, false, true
        end
        if event:getType() == hs.eventtap.event.types.rightMouseUp then
            if firstDown and secondDown then
                if _G.dynamicreload == 1 then
                    quickreload()
                end
                if _G.pressingshit == true then -- if you're holding shift, open the piano menu instead.
                    spawnPianoMenu()
                    timeRMBTime, firstDown, secondDown = 0, false, true
                else
                    spawnPluginMenu()
                    timeRMBTime, firstDown, secondDown = 0, false, true
                    return
                end
            elseif not firstDown then
                firstDown = true
                timeRMBTime = hs.timer.secondsSinceEpoch()
                return
            elseif firstDown then
                secondDown = true
                return
            else
                timeRMBTime, firstDown, secondDown = 0, false, true
                return
            end
        end

        return
    end):start() -- starts the eventtap listener for double right clicks.

function titlebarheight()
    local zoombuttonrect = hs.window.focusedWindow():zoomButtonRect()
    return zoombuttonrect.h + 4
end

function bookmarkfunc() -- this allows you to use the bookmark click stuff. It doesn't work as well on macOS as it does on windows because of all the scaling, but I included it anyway for feature parity.
    local point = {}
    local dimensions = getLiveHsAppObj():mainWindow():frame()
    local bookmark = {}
    bookmark["x"] = _G.bookmarkx + dimensions.x
    bookmark["y"] = _G.bookmarky + dimensions.y + titlebarheight()
    point = hs.mouse.getAbsolutePosition()
    point["__luaSkinType"] = nil
    hs.eventtap.event.newMouseEvent(hs.eventtap.event.types["leftMouseDown"], bookmark):setProperty(hs.eventtap.event
                                                                                                        .properties
                                                                                                        .mouseEventClickState,
        1):post()
    if _G.loadspeed <= 0.5 then
        sleep2 = astSleep(0.1)
    else
        sleep2 = astSleep(0.3)
    end
    hs.eventtap.event.newMouseEvent(hs.eventtap.event.types["leftMouseUp"], bookmark):setProperty(hs.eventtap.event
                                                                                                      .properties
                                                                                                      .mouseEventClickState,
        1):post()
    hs.eventtap.event.newMouseEvent(hs.eventtap.event.types["leftMouseUp"], point):post()
end

debounce2 = 0
-- the plugin names nead to have any newline characters removed
function loadPlugin(plugin)
    pluginCleaned = plugin:match '^%s*(.*%S)' or ''
    hs.eventtap.keyStroke("cmd", "f", 0)
    hs.eventtap.keyStrokes(pluginCleaned)
    tempautoadd = nil

    if hs.eventtap.checkKeyboardModifiers().cmd then -- if you're holding cmd, invert the option for autoadd set in the settings.ini file temporarily.
        if _G.autoadd == 1 then
            tempautoadd = 0
        elseif _G.autoadd == 0 then
            tempautoadd = 1
        end
    else
        tempautoadd = _G.autoadd
    end

    print("tempautoadd = " .. tempautoadd .. " and _G.autoadd = " .. _G.autoadd)

      local sleep = astSleep(0.6)
      hs.eventtap.keyStroke({}, "return", 0)
      local sleep = astSleep(0.2)
      hs.eventtap.keyStroke({}, "return", 0)
      hs.eventtap.keyStroke({}, "escape", 0)
      local sleep = astSleep(0.2)
      hs.eventtap.keyStroke({"cmd", "alt"}, "5", 0)
  
    if _G.resettobrowserbookmark == 1 then
        if _G.loadspeed <= 0.5 then
            sleep2 = astSleep(0.1)
        else
            sleep2 = astSleep(0.3)
        end

        if sleep2 ~= nil then
            bookmarkfunc()
        end
    end
    return

end

-- piano macro stuff
-- this is a seperate eventtap event for the piano roll macro and contains all of the piano roll macro functionality.

buttonstatevar = false
local keyHandler = function(e)
    local buttonstate = e:getButtonState(0)
    local buttonstate2 = e:getButtonState(1)
    local clickState = hs.eventtap.event.properties.mouseEventClickState
    if buttonstate == true and _G.buttonstatevar == false then
        _G.buttonstatevar = true
        local point = {}
        point = hs.mouse.getAbsolutePosition()
        point["__luaSkinType"] = nil
        hs.eventtap.event.newMouseEvent(hs.eventtap.event.types["leftMouseDown"], point):setProperty(clickState, 1)
            :post()
        hs.eventtap.event.newMouseEvent(hs.eventtap.event.types["leftMouseUp"], point):setProperty(clickState, 1):post()
        hs.timer.usleep(6000)
        hs.eventtap.event.newMouseEvent(hs.eventtap.event.types["leftMouseDown"], point):setProperty(clickState, 2)
            :post()
        -- print("clicc")
    elseif buttonstate == false and _G.buttonstatevar == true then
        _G.buttonstatevar = false
        local point = {}
        point = hs.mouse.getAbsolutePosition()
        point["__luaSkinType"] = nil
        hs.eventtap.event.newMouseEvent(hs.eventtap.event.types["leftMouseUp"], point):setProperty(clickState, 2):post()
        -- print("unclicc")
        if _G.pressingshit == true then
            _G.shitvar = 1
        end
        if _G.shitvar == 1 and _G.pressingshit == false then
            _G.shitvar = 0
            _G.stampselect = nil
            return
        end
        if _G.stampselect ~= nil then
            _G.stampselect()
            if pressingshit == false then
                _G.stampselect = nil
                _G.shitvar = 0
            end
        end
    end
    -- if buttonstate2 == true and not hs.eventtap.checkKeyboardModifiers().shift == true then -- macro for showing automation
    --   -- print("right clicc")
    --   if firstRightClick then
    --     firstRightClick:stop()
    --   end
    --   if firstDown ~= nil or secondDown ~= nil then
    --     timeRMBTime, firstDown, secondDown = 0, false, true
    --   end
    --   firstRightClick:start()
    --   hs.eventtap.keyStroke({}, "down", 0)
    --   hs.eventtap.keyStroke({}, "return", 0)
    -- elseif buttonstate2 == true and hs.eventtap.checkKeyboardModifiers().shift == true then -- macro for showing automation in a new lane
    --   -- print("right clicc with shift")
    --   -- local sleep = hs.osascript.applescript([[delay 0.01]])
    --   if firstRightClick then
    --     firstRightClick:stop()
    --   end
    --   if firstDown ~= nil or secondDown ~= nil then
    --     timeRMBTime, firstDown, secondDown = 0, false, true
    --   end
    --   hs.eventtap.keyStroke({}, "down", 0)
    --   hs.eventtap.keyStroke({}, "down", 0)
    --   hs.eventtap.keyStroke({}, "return", 0)
    --   firstRightClick:start()
    -- end
end

-- this is the hammerspoon equivalent of autohotkey's "getKeyState"
keyhandlervar = false
_G.pressingshit = false
modifierHandler = hs.eventtap.new({hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp,
                                         hs.eventtap.event.types.flagsChanged}, function(e)

    local keycode = e:getKeyCode()
    local eventtype = e:getType()
    -- TODO: Implement high verbosity debugging and then uncomment this
    -- print(string.format([[modifierHandler(): keycode: %s (set macro %s), eventtype: %s, keyhandlervar: %s]], keycode, _G.pianorollmacro, eventtype, _G.keyhandlervar))
    if keycode == _G.pianorollmacro and eventtype == hs.eventtap.event.types.keyDown and _G.keyhandlervar == false then -- if the keyhandler is on, the event function above will start
        print("keyhandler on")
        _G.keyhandlervar = true
        keyhandlerevent = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown, hs.eventtap.event.types.leftMouseUp,
                                           hs.eventtap.event.types.rightMouseDown}, keyHandler):start()
    elseif keycode == _G.pianorollmacro and eventtype == hs.eventtap.event.types.keyUp and _G.keyhandlervar == true then -- module.keyListener then
        print("keyhandler off")
        _G.keyhandlervar = false
        keyhandlerevent:stop()
        keyhandlerevent = nil
    end

    local flags = e:getFlags()
    local onlyShiftPressed = false
    for k, v in pairs(flags) do
        onlyShiftPressed = v and k == "shift"
        if not onlyShiftPressed then
            break
        end
    end

    if onlyShiftPressed and _G.pressingshit == false then
        _G.pressingshit = true
        -- print("shit on")
        -- however, adding additional modifiers afterwards is ok... its only when we have no flags that we switch back off
    elseif not next(flags) and _G.pressingshit == true then
        -- print("shit off")
        _G.pressingshit = false
    end

    return false
end)

if _G.nomacro == false then
    modifierHandler:start()
end

----------------------------
--	Cheats and eastereggs --
----------------------------

function cheatmenu()
    local button, enteredcheat = hs.dialog.textPrompt(
        "A mysterious aura surrounds you...",
        "Enter cheat",
        "",
        "Ok",
        "Cancel"
    )
    enteredcheat = enteredcheat:gsub([[.*(.*)%(%"]], "%1")
    enteredcheat = enteredcheat:gsub([[(.*)%".*]], "%1")
    enteredcheat = enteredcheat:lower()
    if button == "Cancel" then
        return false
    elseif button == "Ok" then
        if enteredcheat == "" then
            return false
        elseif enteredcheat == "gaster" then
            os.exit()
        elseif enteredcheat == "collab bro" or enteredcheat == "als" or enteredcheat == "adg" then
            if astBlockingQuery(
                programName,
                [[Doing this will exit your current project without saving. Are you sure?]]
            ) == true then
                getLiveHsAppObj():kill()
                hs.eventtap.keyStroke({"shift"}, "D", 0)
                while true do
                    if getLiveHsAppObj() == nil then
                        break
                    else
                        astSleep(1)
                    end
                end
                print("live is closed")
                ShellCreateDirectory(JoinPaths(ScriptUserResourcesPath, "als Lessons"))
                ShellCopy(JoinPaths(BundleResourceAssetsPath, JoinPaths("als Lessons", "lessonsEN.txt")), JoinPaths(ScriptUserResourcesPath, "als Lessons"))
                ShellCopy(JoinPaths(BundleResourceAssetsPath, "als.als"), ScriptUserResourcesPath)
                print("done cloning project")
                hs.osascript.applescript([[delay 2
          tell application "Finder" to open POSIX file "]] .. GetDataPath([[resources/als.als"]]))
                return true
            end

        elseif enteredcheat == "303" or enteredcheat == "sylenth" then
            HSPlayAudioFile(JoinPaths(BundleResourceAssetsPath, "arp303.mp3"), "thank you for trying this demo")

        elseif enteredcheat == "image line" or enteredcheat == "fl studio" then
            HSPlayAudioFile(JoinPaths(BundleResourceAssetsPath, "flstudio.mp3"))

        elseif enteredcheat == "ghost" or enteredcheat == "ilwag" or enteredcheat == "lvghst" then
            HSPlayAudioFile(JoinPaths(BundleResourceAssetsPath, "lvghst.mp3"))

        elseif enteredcheat == "live enhancement sweet" or enteredcheat == "les" or enteredcheat == "sweet" then
            HSPlayAudioFile(JoinPaths(BundleResourceAssetsPath, "LES_vox.wav"))

        elseif enteredcheat == "yo twitter" or enteredcheat == "twitter" then
            HSPlayAudioFile(JoinPaths(BundleResourceAssetsPath, "yotwitter.mp3"))
            hs.osascript.applescript([[open location "https://twitter.com/aevitunes"
      open location "https://twitter.com/sylvianyeah"
      open location "https://twitter.com/DylanTallchief"
      open location "https://twitter.com/nyteout"
      open location "https://twitter.com/InvertedSilence"
      open location "https://twitter.com/FalseProdigyUS"
      open location "https://twitter.com/DirectOfficial"]])

        elseif enteredcheat == "owo" or enteredcheat == "uwu" or enteredcheat == "what's this" or enteredcheat == "what" then
            HSMakeAlert(programName, [[owowowowoowoowowowoo what's this????????? ^^ nya?]])

        elseif enteredcheat == "subscribe to dylan tallchief" or enteredcheat == "#dylongang" or enteredcheat ==
            "dylan tallchief" or enteredcheat == "dylantallchief" then
            hs.osascript.applescript([[open location "https://www.youtube.com/c/DylanTallchief?sub_confirmation=1"]])
        end
    end
end

------------------------------
--	Timers and app watcher	--
------------------------------

function disablemacros() -- this function stops all of the eventtap events, causing the shortcuts to be disabled.
    threadsenabled = false
    -- hs.alert.show("eventtap threads disabled")
    if dingodango then
        dingodango:stop()
    end
    directshyper:disable()
    buplicate:disable()
    _G.quickmacro:stop()
    firstRightClick:stop()

    if vstshortcuts == 1 then
        vstshenabled = 0
        undo:disable()
        redo:disable()
    end

    if keyhandlerevent then
        keyhandlerevent:stop()
    end
    modifierHandler:stop()
end

function enablemacros() -- this function enables all of the eventtap events, causing the shortcuts to be enabled.
  -- hs.alert.show("eventtap threads enabled")
  threadsenabled = true
  if _G.enabledebug == 1 then
      dingodango:start()
  end
  directshyper:enable()
  buplicate:enable()
  _G.quickmacro:start()
  firstRightClick:start()

  if _G.nomacro == false then
      modifierHandler:start()
  end

  -- Currently setting it as a global because it holds up the main
  -- thread for a bit and we don't want to recalculate.
  --
  -- This table may be invalid if the user switches between Live versions,
  -- however unlikely that may be.
  _G.gValidTitleTable = getValidTitles()
end

disablemacros() -- macros are turned off by default because live is never focused at this point in time, hammerspoon is.
-- if it was, the watcher would turn it on again anyway

function setstricttime() -- this function manages the check box in the menu
    local appname = getLiveHsAppObj() -- getting new track title
    if _G.stricttimevar == true then
        _G.stricttimevar = false
        ShellDeleteFile(JoinPaths(ScriptUserResourcesPath, StrictTimeModifier))
        if appname then
            clock:start()
        end
    else
        _G.stricttimevar = true
        ShellOverwriteFile("beta 9", JoinPaths(ScriptUserResourcesPath, StrictTimeModifier))
        if checkLiveFocused() ~= true then
            clock:stop()
        end
    end
    buildMenuBar()
end

function coolfunc(hswindow, appname, straw) -- function that handles saving and loading of project times in ~/.les/resources/time/

    if trackname ~= nil then -- saving old time
        oldtrackname = trackname
        print(_G["timer_" .. oldtrackname])
        ShellCreateDirectory(JoinPaths(ScriptUserResourcesPath, "time"))
        local filepath = GetDataPath([[resources/time/]] .. oldtrackname .. "_time" .. [[.txt]])
        local f2 = io.open(filepath, "r")
        if f2 ~= nil then
            io.close(f2)
            ShellDeleteFile(JoinPaths(JoinPaths(ScriptUserResourcesPath, "time"), oldtrackname .. "_time" .. [[.txt]]))
        end
        ShellOverwriteFile(_G["timer_" .. oldtrackname], JoinPaths(JoinPaths(ScriptUserResourcesPath, "time"), oldtrackname .. "_time" .. [[.txt]]))
        _G["timer_" .. oldtrackname] = nil
    end

    local appname = getLiveHsAppObj() -- getting new track title
    if appname and appname:mainWindow() then
        local mainwindowname = appname:mainWindow():title()
        if string.find(mainwindowname, "%[") ~= nil and string.find(mainwindowname, "%]") ~= nil then
            trackname = (mainwindowname:gsub(".*(.*)%[", ""))
            trackname = (trackname:gsub("%].*(.*)", ""))
            trackname = trackname:gsub("[%p%c%s]", "_")
            print("trackname = " .. trackname)
        else
            trackname = "unsaved_project"
        end
    else
        trackname = nil
        return
    end

    filepath = GetDataPath([[resources/time/]] .. trackname .. "_time" .. [[.txt]]) -- loading old time (if it exists)
    local f = io.open(filepath, "r")
    if f ~= nil then
        print("timer file found")
        local lines = {}
        for line in f:lines() do
            print("old timer found for this project: " .. line)
            _G["timer_" .. trackname] = line
        end
        return true
    else
        return
    end
end
windowfilter = hs.window.filter.new({'Live'}, nil) -- activating the window filter
windowfilter:subscribe(hs.window.filter.windowTitleChanged, coolfunc) -- if the title of the active window changes, execute this function again.

function timerfunc()
    -- function that writes the time and checks for vst windows if nescesary (currently in seconds)
    -- unfortunately I couldn't use the appwatcher for this, because the app watcher doesn't detect window switches within the same application..
    if vstshortcuts == 1 then
        if hs.window.focusedWindow() == nil then
            return
        end
        if string.lower(string.gsub(hs.window.focusedWindow():title(), "(.*)/.*$", "%1")) == "kick 2" then
            if vstshenabled == 0 then
                print("vst window found")
                vstshenabled = 1
                undo:enable()
                redo:enable()
            end
        elseif vstshenabled == 1 then
            print("vst shortcuts disabled in-daw")
            vstshenabled = 0
            undo:disable()
            redo:disable()
        end
    end

    if trackname == nil then
        coolfunc()
    end
    if trackname ~= nil then
        if _G["timer_" .. trackname] == nil then
            _G["timer_" .. trackname] = 1
        else
            _G["timer_" .. trackname] = _G["timer_" .. trackname] + 1
        end
    end
end
clock = hs.timer.new(1, timerfunc)

function requesttime() -- this is the function for when someone checks the current project time. Formatting the seconds into hours/minutes/seconds and presenting it in a nice dialog box.
    local currenttime = nil
    local response = nil

    if trackname == nil then
        response = hs.dialog.blockAlert("There was no open project detected.",
            "Please open or focus Live for a second and try again.", "Ok")
        return
    end

    if _G["timer_" .. trackname] <= 0 or _G["timer_" .. trackname] == nil then
        currenttime = "0 hours, 0 minutes, and 0 seconds"
    else
        hours = string.format("%02.f", math.floor(_G["timer_" .. trackname] / 3600));
        mins = string.format("%02.f", math.floor(_G["timer_" .. trackname] / 60 - (hours * 60)));
        secs = string.format("%02.f", math.floor(_G["timer_" .. trackname] - hours * 3600 - mins * 60));
        if hours == "00" or hours == nil then
            hours = "0"
        else
            hours = hours:match("0*(%d+)")
        end
        if mins == "00" or mins == nil then
            mins = "0"
        else
            mins = mins:match("0*(%d+)")
        end
        currenttime = hours .. " hours, " .. mins .. " minutes, and " .. secs .. " seconds"
    end

    print(currenttime)

    if trackname == "unsaved_project" then
        response = hs.dialog.blockAlert("Time spent in unsaved projects:", currenttime, "Ok", "Reset Time",
            "NSCriticalAlertStyle")
    else
        response = hs.dialog.blockAlert("Time spent inside the [" .. trackname .. "] project:", currenttime, "Ok",
            "Reset Time", "NSCriticalAlertStyle")
    end

    if response == "Reset Time" then
        response = hs.dialog.blockAlert("Are you sure?", "This action cannot be undone", "No", "Yes",
            "NSCriticalAlertStyle")
        if response == "Yes" then
            ShellDeleteFile(JoinPaths(JoinPaths(ScriptUserResourcesPath, "time"), trackname .. "_time" .. [[.txt]]))
            coolfunc()
        end
    end
    hs.application.launchOrFocusByBundleID(targetBundle) -- focusses live again when closing the dialog box.
end

threadsenabled = false
appwatcher = hs.application.watcher.new(function(name, event, app)
    appwatch(name, event, app)
end):start() -- terminates hotkeys when ableton is unfocussed
i = 1
function appwatch(name, event, app)
    if hs.window.focusedWindow() == nil then
        goto epicend
        return
    end

    if event == hs.application.watcher.activated or hs.application.watcher.deactivated then
        if hs.window.focusedWindow() then
            if hs.window.focusedWindow():application():bundleID() == targetBundle then
                if threadsenabled == false then
                    print("live is in window focus")
                    enablemacros()
                    clock:start()
                    _G.pausebutton:start()
                end
            elseif threadsenabled == true then
                print("live is not in window focus")
                disablemacros()
                if _G.stricttimevar == true then
                    clock:stop()
                    _G.pausebutton:stop()
                else
                    print("clock wasn't stopped because strict time is off")
                end
            end
        end
    end
    ::epicend::

    if event == hs.application.watcher.terminated then
        if clock:running() == true then
            clock:stop()
        end
        coolfunc()
        print("Live was quit")
    end
end

hs.dockIcon(false) -- removes the hammerspoon icon from the dock
if console then
    console:close()
end -- attempting to close the console one more time, just in case.
