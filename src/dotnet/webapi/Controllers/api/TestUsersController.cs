using Microsoft.AspNetCore.Mvc;

namespace webapi.Controllers;

// [Route("api/[controller]")] // => api/TestUsers
[Route("api/test-users/")]
public class TestUsersController : ControllerBase
{
  [HttpGet()]
  public string Index()
  {
    return "api get test users";
  }

  [HttpGet("{id}")]
  public string Show(int id)
  {
    Console.WriteLine("==== show");
    Console.WriteLine(id.GetType());
    Console.WriteLine(id);
    return $"api get test users {id}";
  }

  [HttpPost()]
  public string Create()
  {
    return "api post test users";
  }

  [HttpPut("{id}")]
  public string Update(int id)
  {
    return "api put test users";
  }

  [HttpDelete("{id}")]
  public string Delete(int id)
  {
    return "api delete test users";
  }
}
