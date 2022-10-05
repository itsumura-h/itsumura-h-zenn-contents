using Microsoft.AspNetCore.Mvc;

namespace webapi.Controllers;

[Route("")]
public class IndexController : Controller
{
  [HttpGet("")]
  public IActionResult Index()
  {
    return View("Views/IndexView.cshtml");
  }
}
