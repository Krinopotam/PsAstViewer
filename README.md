# PsAstViewer

![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue?logo=powershell)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey?logo=windows)
![License](https://img.shields.io/badge/License-MIT-green)
![UI](https://img.shields.io/badge/UI-WinForms-orange)

**PsAstViewer** is a PowerShell module designed for convenient visualization and exploration of the PowerShell Abstract Syntax Tree (AST).  
It provides an interactive **WinForms-based** interface that allows you to inspect, navigate, and dynamically update the AST structure of PowerShell scripts.

> ⚠️ **Note:** This module works only on **Windows**, since it uses WinForms.  
> Minimum PowerShell version: **5.1**

---

## 📦 Installation

1. Clone or download this repository:
   ```powershell
   git clone https://github.com/Krinopotam/PsAstViewer.git
   ```

2. Import the module in PowerShell:
   ```powershell
   Import-Module .\PsAstViewer\PsAstViewer.psd1
   ```

3. (Optional) To make the module available globally, copy the folder to one of the PowerShell module paths, for example:
   ```powershell
   $env:USERPROFILE\Documents\WindowsPowerShell\Modules\PsAstViewer
   ```

---

## 🚀 Usage

To launch the AST Viewer, run:

```powershell
Show-AstViewer -Path ".\example.ps1"
```

This will open a graphical window displaying the Abstract Syntax Tree of the specified PowerShell script.

---

## 🧩 Requirements

- **Operating System:** Windows only  
- **PowerShell:** Version 5.1 or higher  
- **Dependencies:** Built-in WinForms libraries (no external dependencies)

---

## 🖥️ User Interface Overview

The application window consists of three main panels:

### 1. **AST Tree (Top-Left)**
A **TreeView** control displaying the hierarchical structure of AST nodes.  
Each node represents an element of the PowerShell script (such as a statement, expression, or parameter).

### 2. **Node Properties (Bottom-Left)**
Displays the **properties** of the currently selected AST node.  
- If a property is itself another AST node, you can **Ctrl + Click** on it to jump directly to that node in the tree.  
- This allows for fast navigation between related elements of the syntax structure.

### 3. **Source Code View (Right)**
An **editable text box** showing the PowerShell source code.  
- When you select an AST node in the tree, the corresponding code region is **highlighted** in this view.  
- If you select another AST node via the properties panel, its code range is **additionally highlighted**, making overlapping regions visible.  
- When you **Ctrl + Click anywhere** in the code editor (not just in a highlighted area), the viewer automatically determines which AST node corresponds to that position, selects it in the tree, and highlights its range in the code.  
- If you **edit the code**, the AST tree and property panels are automatically **reparsed and updated** to reflect the new structure.

This interactive and synchronized interface makes it easy to explore how each code fragment maps to the underlying AST and vice versa.

---

## 📝 Example

```powershell
# View and explore the AST structure of a script
Show-AstViewer -Path "C:\Scripts\Test.ps1"
```

You can edit the script directly in the right-hand pane — changes will trigger automatic AST regeneration.

---

## ⚙️ Technical Details

PsAstViewer internally uses the PowerShell parser from  
`System.Management.Automation.Language.Parser`  
to parse scripts and construct their Abstract Syntax Trees.  
The visualization is dynamically generated based on the resulting AST objects and their properties.

---

## 📄 License

This project is distributed under the **MIT License**.  
See the [LICENSE](https://github.com/Krinopotam/PsAstViewer/blob/master/LICENSE) file for details.
