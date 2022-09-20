using Microsoft.AspNetCore.Mvc;

namespace benchmark.Controllers;

[Route("")]
public class BenchmarkController : Controller
{

  [HttpGet("plaintext")]
  public string Plaintext()
  {
    return "plaintext";
  }

  [HttpGet("json")]
  public object Json()
  {
    return new {message = "Hello, World!"};
  }

  [HttpGet("view")]
  public IActionResult Index()
  {
    return View("Views/Benchmark/Index.cshtml");
  }
}
