use atuin_dotfiles::store::{var::VarStore, AliasStore};
use eyre::Result;

pub fn init_static(disable_up_arrow: bool, disable_ctrl_r: bool) {
    let base = include_str!("../../../shell/atuin.ps1");

    let (bind_ctrl_r, bind_up_arrow) = if std::env::var("ATUIN_NOBIND").is_ok() {
        (false, false)
    } else {
        (!disable_ctrl_r, !disable_up_arrow)
    };

    fn bool(value: bool) -> &'static str {
        if value {
            "$true"
        } else {
            "$false"
        }
    }

    println!("{base}");
    println!(
        "Enable-AtuinSearchKeys -CtrlR {} -UpArrow {}",
        bool(bind_ctrl_r),
        bool(bind_up_arrow)
    );
}

pub async fn init(
    _aliases: AliasStore,
    _vars: VarStore,
    disable_up_arrow: bool,
    disable_ctrl_r: bool,
) -> Result<()> {
    init_static(disable_up_arrow, disable_ctrl_r);

    // dotfiles are not supported yet

    Ok(())
}
